// SPDX-License-Identifier: GPL-2.0
/*
 * Squelette de module : sonde du capteur Touch ID (biosensor,mesa) sur SPI.
 * HORS LIGNE, JAMAIS COMPILE NI TESTE sur du materiel. Ecrit a partir des docs du repo seulement :
 *   - docs/sensor_hw.md, docs/driver_plan.md (etape 3), driver/sepreplay/sensor.py (octets du statut).
 *
 * Ce module ne parle PAS au SEP. Il alimente le capteur (GPIO), lit 16 octets sur le bus SPI et les affiche.
 * Desactive par defaut : rien ne se passe sans enable=1.
 *
 * INCONNU : le capteur demande-t-il une trame de requete avant d'envoyer le statut ? Aucune trame de requete
 * de statut n'est documentee ici (docs : seule la demande de lecture 80 13 est connue, hypothese). On fait donc
 * une simple lecture de 16 octets, sans rien ecrire. Si le capteur ne repond pas, c'est une information.
 */
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/spi/spi.h>

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "1 = alimenter le capteur et lire le statut (defaut 0 : ne rien faire)");

#define MESA_STATUS_LEN	16

/* Entete verifie (16/16 traces, docs/verification_status.md) : 80 20 00 | longueur u32 LE = 0x10. */
static const u8 mesa_status_head[7] = { 0x80, 0x20, 0x00, 0x10, 0x00, 0x00, 0x00 };
/* Exemple observe sous macOS (driver/tests/test_step3_sensor.py) ; le reste du statut est INCONNU. */

struct mesa {
	struct spi_device *spi;
	struct gpio_desc *pwr;
	u32 on_delay;
	u32 off_delay;
};

static int mesa_read_status(struct mesa *m)
{
	u8 *buf;
	int ret;

	buf = kzalloc(MESA_STATUS_LEN, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;

	ret = spi_read(m->spi, buf, MESA_STATUS_LEN);	/* lecture seule, rien n'est ecrit sur le bus */
	if (ret) {
		dev_err(&m->spi->dev, "lecture SPI echouee: %d\n", ret);
		goto out;
	}

	dev_info(&m->spi->dev, "statut: %*ph\n", MESA_STATUS_LEN, buf);
	if (!memcmp(buf, mesa_status_head, sizeof(mesa_status_head)))
		dev_info(&m->spi->dev, "entete conforme a celle vue sous macOS (80 20 00 10000000)\n");
	else
		dev_warn(&m->spi->dev, "entete differente de 80 20 00 10000000 (voir README: inconnus)\n");
out:
	kfree(buf);
	return ret;
}

static int mesa_probe(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	struct mesa *m;
	int ret;

	if (!enable) {
		dev_info(dev, "desactive (enable=0), aucune action\n");
		return -ENODEV;
	}

	m = devm_kzalloc(dev, sizeof(*m), GFP_KERNEL);
	if (!m)
		return -ENOMEM;
	m->spi = spi;

	/* Unite supposee : millisecondes (A VERIFIER). */
	m->on_delay = 7;
	m->off_delay = 10;
	device_property_read_u32(dev, "apple,power-on-delay", &m->on_delay);
	device_property_read_u32(dev, "apple,power-off-delay", &m->off_delay);

	m->pwr = devm_gpiod_get(dev, "pwr", GPIOD_OUT_LOW);
	if (IS_ERR(m->pwr))
		return dev_err_probe(dev, PTR_ERR(m->pwr), "GPIO d'alimentation absent\n");

	spi->max_speed_hz = min_not_zero(spi->max_speed_hz, 8000000U);
	ret = spi_setup(spi);
	if (ret)
		return ret;

	dev_info(dev, "alimentation du capteur (delai %u)\n", m->on_delay);
	gpiod_set_value_cansleep(m->pwr, 1);
	msleep(m->on_delay);

	ret = mesa_read_status(m);

	gpiod_set_value_cansleep(m->pwr, 0);
	msleep(m->off_delay);
	dev_info(dev, "capteur coupe, fin de la sonde\n");

	/* Sonde pure : on ne reste pas lie au capteur. */
	return ret ? ret : -ENODEV;
}

static const struct of_device_id mesa_of_match[] = {
	{ .compatible = "biosensor,mesa" },
	{ }
};
MODULE_DEVICE_TABLE(of, mesa_of_match);

static struct spi_driver mesa_driver = {
	.driver = {
		.name = "mesa-probe",
		.of_match_table = mesa_of_match,
	},
	.probe = mesa_probe,
};
module_spi_driver(mesa_driver);

MODULE_DESCRIPTION("Sonde en lecture seule du capteur Touch ID (squelette, non teste)");
MODULE_LICENSE("GPL");
