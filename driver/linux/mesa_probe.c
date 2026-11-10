// SPDX-License-Identifier: GPL-2.0
/*
 * « Bonjour » au capteur Touch ID (ADT "biosensor,mesa", bus spi2 du j314c) depuis Linux.
 *
 * Refait la séquence de tools/mesa_hello.sh, vérifiée 2 fois sur le Mac depuis m1n1
 * (docs/verification_status.md SPI-3, docs/sensor_hw.md « Essai sans macOS »), et rien d'autre :
 * alimentation, réveil, état, identité, état, lecture de l'identité, état, extinction.
 * Uniquement les 4 trames en clair (0x78, 0x10, 0x70, 0x13). Aucune trame chiffrée, rien vers le SEP.
 *
 * Ne fait rien sans le paramètre enable=1. JAMAIS LANCÉ sur du matériel sous Linux.
 * Écrit à partir de docs/ et de l'API publique Linux ; aucun code Apple.
 */
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/slab.h>
#include <linux/spi/spi.h>
#include <linux/string.h>

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "1 = allumer le capteur et lire son identité (défaut 0 : ne rien faire)");

#define MESA_HDR_LEN	7	/* 80 <cmd> <longueur, 16 bits gros-boutiste> 00 00 00 */
#define MESA_STATUS_LEN	16	/* réponse d'état : 80 20 00 10 ... */
#define MESA_ID_LEN	0x1b
#define MESA_MAX_HZ	8000000	/* fréquence de l'ADT ; voir le .dtsi pour 6 ou 8 MHz */
#define MESA_GAP_MS	10	/* pause entre deux échanges, comme mesa_hello.sh */

static const u8 mesa_wake[] = { 0x80, 0x78, 0x00, 0x07, 0x00, 0x00, 0x00 };
static const u8 mesa_get_id[] = { 0x80, 0x70, 0x00, 0x07, 0x00, 0x00, 0x00 };
static const u8 mesa_get_status[] = { 0x80, 0x10, 0x00, 0x07, 0x00, 0x00, 0x00 };
static const u8 mesa_read_id[] = { 0x80, 0x13, 0x00, 0x0b, 0x00, 0x00, 0x00, MESA_ID_LEN, 0x00, 0x00, 0x00 };
static const u8 mesa_status_head[] = { 0x80, 0x20, 0x00, 0x10 };
/* Identité lue sous macOS (C18, C19) et depuis m1n1 (MESA-HELLO, 2 essais). */
static const u8 mesa_id_expected[MESA_ID_LEN] = {
	0x80, 0xd4, 0x00, 0x1b, 0x00, 0x00, 0x00, 0x00, 0x70, 0x02, 0x19, 0xc0, 0x5c, 0x0f,
	0xd2, 0xaa, 0x34, 0x9a, 0x81, 0xc7, 0x6e, 0x03, 0x02, 0x00, 0xd8, 0x75, 0x76,
};

/* Tampons alloués (pas sur la pile : exigence de l'API SPI). */
struct mesa_bufs {
	u8 tx[32];
	u8 rx[32];
};

/*
 * Un échange = un spi_message à lui seul (macOS fait des échanges séparés).
 * Émet cmd complété par des zéros jusqu'à len ; reçoit len octets si want_rx.
 */
static int mesa_xfer(struct spi_device *spi, struct mesa_bufs *b, const char *what,
		     const u8 *cmd, size_t cmd_len, size_t len, bool want_rx)
{
	struct spi_transfer t = {
		.tx_buf = b->tx,
		.rx_buf = want_rx ? b->rx : NULL,
		.len = len,
		.bits_per_word = 8,
	};
	int ret;

	memset(b->tx, 0, sizeof(b->tx));
	memset(b->rx, 0, sizeof(b->rx));
	if (cmd_len)
		memcpy(b->tx, cmd, cmd_len);

	ret = spi_sync_transfer(spi, &t, 1);
	if (ret) {
		dev_err(&spi->dev, "%s : échange SPI échoué (%d)\n", what, ret);
		return ret;
	}
	dev_info(&spi->dev, "%s TX %*ph\n", what, (int)len, b->tx);
	if (want_rx)
		dev_info(&spi->dev, "%s RX %*ph\n", what, (int)len, b->rx);
	msleep(MESA_GAP_MS);
	return 0;
}

/*
 * État : 7 octets de demande + 16 zéros, lecture simultanée de 0x17 octets ; la réponse commence à l'octet 7.
 * Rend le nombre d'octets en attente annoncé (octets 12 et 13 de la réponse), -ENOMSG si l'état n'est pas reconnu.
 */
static int mesa_status(struct spi_device *spi, struct mesa_bufs *b)
{
	const u8 *st = b->rx + MESA_HDR_LEN;
	int ret;

	ret = mesa_xfer(spi, b, "état", mesa_get_status, sizeof(mesa_get_status),
			MESA_HDR_LEN + MESA_STATUS_LEN, true);
	if (ret)
		return ret;
	if (memcmp(st, mesa_status_head, sizeof(mesa_status_head))) {
		dev_warn(&spi->dev, "état non reconnu (attendu 80 20 00 10 à l'octet 7)\n");
		return -ENOMSG;
	}
	return st[12] | st[13] << 8;
}

static int mesa_hello(struct spi_device *spi, struct mesa_bufs *b)
{
	int ret, pending;

	ret = mesa_xfer(spi, b, "réveil", mesa_wake, sizeof(mesa_wake), sizeof(mesa_wake), false);
	if (ret)
		return ret;
	ret = mesa_status(spi, b);
	if (ret < 0 && ret != -ENOMSG)
		return ret;
	ret = mesa_xfer(spi, b, "identité", mesa_get_id, sizeof(mesa_get_id), sizeof(mesa_get_id), false);
	if (ret)
		return ret;
	pending = mesa_status(spi, b);
	if (pending < 0 && pending != -ENOMSG)
		return pending;
	dev_info(&spi->dev, "réponse en attente : %d octets\n", pending < 0 ? 0 : pending);

	if (pending != MESA_ID_LEN) {
		dev_warn(&spi->dev, "RÉSULTAT : pas d'identité lue (le capteur n'annonce pas 0x1b octets)\n");
		return 0;
	}

	ret = mesa_xfer(spi, b, "demande", mesa_read_id, sizeof(mesa_read_id), sizeof(mesa_read_id), false);
	if (ret)
		return ret;
	ret = mesa_xfer(spi, b, "réponse", NULL, 0, MESA_ID_LEN, true);
	if (ret)
		return ret;
	if (!memcmp(b->rx, mesa_id_expected, MESA_ID_LEN))
		dev_info(&spi->dev, "RÉSULTAT : IDENTITÉ IDENTIQUE à celle lue sous macOS et depuis m1n1\n");
	else
		dev_warn(&spi->dev, "RÉSULTAT : réponse différente de l'identité attendue\n");

	ret = mesa_status(spi, b);
	return ret < 0 && ret != -ENOMSG ? ret : 0;
}

static int mesa_probe(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	struct device *host = spi->controller->dev.parent;
	struct gpio_desc *pwr;
	struct mesa_bufs *b;
	int ret;

	if (!enable)
		return -ENODEV;		/* défaut : aucune action, aucune écriture */

	if (!spi->max_speed_hz || spi->max_speed_hz > MESA_MAX_HZ)
		return dev_err_probe(dev, -EINVAL, "spi-max-frequency absent ou > 8 MHz : arrêt\n");

	b = devm_kzalloc(dev, sizeof(*b), GFP_KERNEL);
	if (!b)
		return -ENOMEM;

	/* Mode vérifié : CPHA = 1, CPOL = 0, 8 bits. Pas de chip-select sur ce bus : voir README (SPI_NO_CS). */
	spi->mode = (spi->mode & ~SPI_MODE_X_MASK) | SPI_MODE_1;
	spi->bits_per_word = 8;
	ret = spi_setup(spi);
	if (ret)
		return dev_err_probe(dev, ret, "réglage SPI refusé\n");

	/* Première écriture : la broche d'alimentation passe en sortie à 0. */
	pwr = devm_gpiod_get(dev, "pwr", GPIOD_OUT_LOW);
	if (IS_ERR(pwr))
		return dev_err_probe(dev, PTR_ERR(pwr), "GPIO d'alimentation (pwr-gpios) absent\n");

	/* Garde le contrôleur spi2 alimenté pendant toute la séquence (pas de coupure entre deux échanges). */
	ret = pm_runtime_resume_and_get(host);
	if (ret)
		return dev_err_probe(dev, ret, "contrôleur SPI non alimenté\n");

	dev_info(dev, "alimentation du capteur, %u Hz, mode %#x\n", spi->max_speed_hz, spi->mode);
	msleep(40);
	gpiod_set_value_cansleep(pwr, 1);
	msleep(60);

	ret = mesa_hello(spi, b);

	gpiod_set_value_cansleep(pwr, 0);
	msleep(20);
	pm_runtime_put(host);
	dev_info(dev, "capteur éteint, fin (%d)\n", ret);

	/* Essai unique : on ne reste pas lié au capteur (recharger le module pour recommencer). */
	return ret ? ret : -ENODEV;
}

static const struct of_device_id mesa_of_match[] = {
	{ .compatible = "biosensor,mesa" },
	{ }
};
MODULE_DEVICE_TABLE(of, mesa_of_match);

static const struct spi_device_id mesa_spi_id[] = {
	{ "mesa" },
	{ }
};
MODULE_DEVICE_TABLE(spi, mesa_spi_id);

static struct spi_driver mesa_driver = {
	.driver = {
		.name = "mesa-probe",
		.of_match_table = mesa_of_match,
	},
	.probe = mesa_probe,
	.id_table = mesa_spi_id,
};
module_spi_driver(mesa_driver);

MODULE_DESCRIPTION("Bonjour au capteur Touch ID : identité et état, trames en clair seulement");
MODULE_LICENSE("GPL");
