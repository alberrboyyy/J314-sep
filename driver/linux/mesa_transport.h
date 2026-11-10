/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Transport du capteur Touch ID "mesa" (ADT "biosensor,mesa", bus spi2 du j314c).
 *
 * Primitives réutilisables, SANS aucune logique de test : prendre/relâcher le
 * capteur, l'allumer/l'éteindre, un échange SPI, lire l'état, lire une réponse
 * en attente. Le vrai pilote (phase ultérieure) s'appuiera sur ces fonctions ;
 * le « bonjour » de mesa_probe.c n'en est que le premier client.
 *
 * Trames en clair seulement (0x78, 0x10, 0x70, 0x13). Rien vers le SEP.
 * Séquence vérifiée 2 fois depuis m1n1 et une fois depuis Linux (docs/journal.md,
 * MESA-HELLO et LINUX-HELLO). Écrit à partir de docs/ et de l'API publique Linux ;
 * aucun code Apple.
 */
#ifndef MESA_TRANSPORT_H
#define MESA_TRANSPORT_H

#include <linux/delay.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/gpio/driver.h>
#include <linux/pm_runtime.h>
#include <linux/spi/spi.h>
#include <linux/string.h>
#include <linux/types.h>

#define MESA_MAX_HZ	8000000	/* fréquence de l'ADT ; voir le .dtsi pour 6 ou 8 MHz */
#define MESA_HDR_LEN	7	/* en-tête d'une trame : 80 <cmd> <longueur 16 bits BE> 00 00 00 */
#define MESA_STATUS_LEN	16	/* corps d'une réponse d'état : 80 20 00 10 ... */
#define MESA_GAP_MS	10	/* pause entre deux échanges, comme mesa_hello.sh */

/* Délais de la séquence d'alimentation (vérifiés dans mesa_hello.sh / MESA-HELLO). */
#define MESA_PWR_PRE_MS	40	/* broche à 0 avant d'allumer */
#define MESA_PWR_ON_MS	60	/* attente après la montée de l'alimentation */
#define MESA_PWR_OFF_MS	20	/* attente après extinction */

/* Broche « donnée prête » (gpio0 195) : active haute, monte quand une réponse est en attente,
 * retombe quand l'AP lit l'état (0x10). Vérifié 2026-11-10 (docs/sensor_hw.md). Lue seulement. */
#define MESA_READY_PIN		195
#define MESA_READY_TIMEOUT_MS	50	/* attente max de la montée ; au-delà on continue (repli) */

/* En-tête d'un état renvoyé par le capteur (à l'octet 7 d'une réponse d'état). */
static const u8 mesa_status_head[] = { 0x80, 0x20, 0x00, 0x10 };
/* Demande d'état : 7 octets, complétée de 16 zéros ; on lit 0x17 octets. */
static const u8 mesa_cmd_status[] = { 0x80, 0x10, 0x00, 0x07, 0x00, 0x00, 0x00 };

/*
 * Capteur en cours de dialogue. tx/rx hors pile (exigence de l'API SPI).
 * Un seul échange est en vol à la fois : ces deux tampons suffisent.
 */
struct mesa_dev {
	struct spi_device *spi;
	struct device	  *host;	/* contrôleur spi2, gardé alimenté pendant la séquence */
	struct gpio_desc  *pwr;		/* alimentation du capteur, actif haut (gpio0 196) */
	struct gpio_desc  *ready;	/* broche « donnée prête » gpio0 195, lue seulement (NULL si absente) */
	u8 tx[32];
	u8 rx[32];
};

/*
 * Prend le capteur : règle le mode SPI vérifié (CPHA=1, CPOL=0, 8 bits ; pas de
 * chip-select câblé, voir README), récupère la broche d'alimentation (laissée à 0)
 * et garde le contrôleur spi2 alimenté. N'allume pas encore le capteur.
 * Retour 0, ou négatif (déjà journalisé via dev_err_probe).
 */
static inline int mesa_acquire(struct mesa_dev *md, struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	int ret;

	memset(md, 0, sizeof(*md));
	md->spi = spi;
	md->host = spi->controller->dev.parent;

	if (!spi->max_speed_hz || spi->max_speed_hz > MESA_MAX_HZ)
		return dev_err_probe(dev, -EINVAL, "spi-max-frequency absent ou > 8 MHz : arrêt\n");

	spi->mode = (spi->mode & ~SPI_MODE_X_MASK) | SPI_MODE_1;
	spi->bits_per_word = 8;
	ret = spi_setup(spi);
	if (ret)
		return dev_err_probe(dev, ret, "réglage SPI refusé\n");

	/* Première écriture : la broche d'alimentation passe en sortie à 0. */
	md->pwr = devm_gpiod_get(dev, "pwr", GPIOD_OUT_LOW);
	if (IS_ERR(md->pwr))
		return dev_err_probe(dev, PTR_ERR(md->pwr), "GPIO d'alimentation (pwr-gpios) absent\n");

	/* Broche « donnée prête » (même contrôleur gpio0 que pwr), lue seulement ; absente = non bloquant. */
	md->ready = gpio_device_get_desc(gpiod_to_gpio_device(md->pwr), MESA_READY_PIN);
	if (IS_ERR(md->ready))
		md->ready = NULL;

	/* Garde spi2 alimenté pendant toute la séquence (pas de coupure entre deux échanges). */
	ret = pm_runtime_resume_and_get(md->host);
	if (ret)
		return dev_err_probe(dev, ret, "contrôleur SPI non alimenté\n");

	return 0;
}

/*
 * Attend que la broche « donnée prête » monte (réponse en attente), au plus MESA_READY_TIMEOUT_MS.
 * Scrutation (pas d'interruption) : sûr, ne peut pas bloquer la machine. Repli si la broche est
 * absente ou ne monte pas (on continue, les pauses fixes restent un plancher). Rend 1 si montée vue.
 */
static inline int mesa_wait_ready(struct mesa_dev *md)
{
	int i;

	if (!md->ready)
		return 0;
	for (i = 0; i < MESA_READY_TIMEOUT_MS; i++) {
		if (gpiod_get_raw_value_cansleep(md->ready) == 1)
			return 1;
		msleep(1);
	}
	dev_warn(&md->spi->dev, "broche « donnée prête » pas montée en %d ms (repli pauses fixes)\n",
		 MESA_READY_TIMEOUT_MS);
	return 0;
}

/* Relâche le contrôleur spi2 (la broche est gérée par devm). À appeler après mesa_power_off. */
static inline void mesa_release(struct mesa_dev *md)
{
	pm_runtime_put(md->host);
}

/* Allume le capteur : broche à 0 un instant, puis à 1, avec les attentes vérifiées. */
static inline void mesa_power_on(struct mesa_dev *md)
{
	dev_info(&md->spi->dev, "alimentation du capteur, %u Hz, mode %#x\n",
		 md->spi->max_speed_hz, md->spi->mode);
	msleep(MESA_PWR_PRE_MS);
	gpiod_set_value_cansleep(md->pwr, 1);
	msleep(MESA_PWR_ON_MS);
}

/* Éteint le capteur. */
static inline void mesa_power_off(struct mesa_dev *md)
{
	gpiod_set_value_cansleep(md->pwr, 0);
	msleep(MESA_PWR_OFF_MS);
}

/*
 * Un échange = un spi_message à lui seul (macOS fait des échanges séparés).
 * Émet cmd complété de zéros jusqu'à len ; reçoit len octets si want_rx.
 * Journalise TX (et RX) ; pause de MESA_GAP_MS ensuite.
 */
static inline int mesa_xfer(struct mesa_dev *md, const char *what,
			    const u8 *cmd, size_t cmd_len, size_t len, bool want_rx)
{
	struct spi_transfer t = {
		.tx_buf = md->tx,
		.rx_buf = want_rx ? md->rx : NULL,
		.len = len,
		.bits_per_word = 8,
	};
	int ret;

	if (len > sizeof(md->tx))
		return -EINVAL;

	memset(md->tx, 0, sizeof(md->tx));
	memset(md->rx, 0, sizeof(md->rx));
	if (cmd_len)
		memcpy(md->tx, cmd, cmd_len);

	ret = spi_sync_transfer(md->spi, &t, 1);
	if (ret) {
		dev_err(&md->spi->dev, "%s : échange SPI échoué (%d)\n", what, ret);
		return ret;
	}
	dev_info(&md->spi->dev, "%s TX %*ph\n", what, (int)len, md->tx);
	if (want_rx)
		dev_info(&md->spi->dev, "%s RX %*ph\n", what, (int)len, md->rx);
	msleep(MESA_GAP_MS);
	return 0;
}

/* Émet une commande sans lire de réponse (réveil, identité, demande de lecture). */
static inline int mesa_send(struct mesa_dev *md, const char *what,
			    const u8 *cmd, size_t cmd_len)
{
	return mesa_xfer(md, what, cmd, cmd_len, cmd_len, false);
}

/*
 * Lit une réponse de len octets en attente (émet des zéros). Les octets reçus
 * sont dans md->rx. Utilisé après une demande (ex. 0x13) qui annonce des octets.
 */
static inline int mesa_read(struct mesa_dev *md, const char *what, size_t len)
{
	return mesa_xfer(md, what, NULL, 0, len, true);
}

/*
 * Lit l'état : demande + 16 zéros, lecture de 0x17 octets ; la réponse commence
 * à l'octet 7 (md->rx + MESA_HDR_LEN). Rend le nombre d'octets en attente annoncé
 * (octets 12 et 13 de la réponse), ou -ENOMSG si l'en-tête d'état n'est pas reconnu,
 * ou l'erreur SPI.
 */
static inline int mesa_status(struct mesa_dev *md)
{
	const u8 *st = md->rx + MESA_HDR_LEN;
	int ret;

	ret = mesa_xfer(md, "état", mesa_cmd_status, sizeof(mesa_cmd_status),
			MESA_HDR_LEN + MESA_STATUS_LEN, true);
	if (ret)
		return ret;
	if (memcmp(st, mesa_status_head, sizeof(mesa_status_head))) {
		dev_warn(&md->spi->dev, "état non reconnu (attendu 80 20 00 10 à l'octet 7)\n");
		return -ENOMSG;
	}
	return st[12] | st[13] << 8;
}

#endif /* MESA_TRANSPORT_H */
