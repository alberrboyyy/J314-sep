// SPDX-License-Identifier: GPL-2.0
/*
 * Surveille la broche d'interruption du capteur Touch ID « mesa » (gpio0 195, lue de l'ADT)
 * pendant que le capteur est allumé par Linux seul. 3e client de mesa_transport.h.
 *
 * Séquence : note la broche capteur éteint, allume, note, réveil (0x78), note, puis pendant
 * `duree` secondes : lit la broche toutes les 20 ms et journalise chaque changement ; lit
 * l'état (0x10) toutes les `etat_ms` millisecondes (0 = jamais).
 *
 * La broche est LUE SEULEMENT (gpiod_get_raw_value sur le descripteur du contrôleur, sans la
 * demander ni la reconfigurer) : aucune écriture dans son registre. Trames en clair 0x78 et
 * 0x10 seulement. Rien vers le SEP. Aucun code Apple.
 *
 * Ne fait rien sans enable=1. Ne pas charger avec mesa_probe ou mesa_statloop.
 */
#include <linux/gpio/driver.h>
#include <linux/jiffies.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/slab.h>

#include "mesa_transport.h"

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "1 = allumer le capteur et surveiller sa broche d'interruption (défaut 0)");

static unsigned int duree = 30;
module_param(duree, uint, 0444);
MODULE_PARM_DESC(duree, "durée de la surveillance en secondes (défaut 30)");

static unsigned int etat_ms = 1000;
module_param(etat_ms, uint, 0444);
MODULE_PARM_DESC(etat_ms, "période de lecture de l'état en ms, 0 = ne jamais lire l'état (défaut 1000)");

static unsigned int broche = 195;
module_param(broche, uint, 0444);
MODULE_PARM_DESC(broche, "numéro de la broche à surveiller sur le contrôleur de la broche d'alimentation (défaut 195)");

#define MESA_IRQ_POLL_MS	20

static const u8 mesa_wake[] = { 0x80, 0x78, 0x00, 0x07, 0x00, 0x00, 0x00 };

static int mesa_pin(struct gpio_desc *irq)
{
	return gpiod_get_raw_value_cansleep(irq);
}

static int mesa_irqwatch(struct mesa_dev *md, struct gpio_desc *irq)
{
	struct device *dev = &md->spi->dev;
	unsigned long start, end, next_status;
	int ret, v, prev, changes = 0;

	dev_info(dev, "broche %u capteur éteint : %d\n", broche, mesa_pin(irq));
	mesa_power_on(md);
	dev_info(dev, "broche %u après allumage : %d\n", broche, mesa_pin(irq));
	ret = mesa_send(md, "réveil", mesa_wake, sizeof(mesa_wake));
	if (ret)
		return ret;
	prev = mesa_pin(irq);
	dev_info(dev, "broche %u après réveil : %d\n", broche, prev);

	start = jiffies;
	end = start + secs_to_jiffies(duree);
	next_status = start;
	while (time_before(jiffies, end)) {
		if (etat_ms && time_after_eq(jiffies, next_status)) {
			ret = mesa_status(md);
			if (ret < 0 && ret != -ENOMSG)
				return ret;
			next_status += msecs_to_jiffies(etat_ms);
		}
		v = mesa_pin(irq);
		if (v != prev) {
			changes++;
			dev_info(dev, "BROCHE %u : %d -> %d à t=%u ms\n", broche, prev, v,
				 jiffies_to_msecs(jiffies - start));
			prev = v;
		}
		msleep(MESA_IRQ_POLL_MS);
	}
	dev_info(dev, "RÉSULTAT : %d changement(s) de la broche %u en %u s, valeur finale %d\n",
		 changes, broche, duree, prev);
	return 0;
}

static int mesa_iw_probe(struct spi_device *spi)
{
	struct mesa_dev *md;
	struct gpio_desc *irq;
	int ret;

	if (!enable)
		return -ENODEV;

	md = devm_kzalloc(&spi->dev, sizeof(*md), GFP_KERNEL);
	if (!md)
		return -ENOMEM;

	ret = mesa_acquire(md, spi);
	if (ret)
		return ret;

	/* Même contrôleur que la broche d'alimentation (gpio0) ; lecture seule, pas de demande. */
	irq = gpio_device_get_desc(gpiod_to_gpio_device(md->pwr), broche);
	if (IS_ERR(irq)) {
		mesa_release(md);
		return dev_err_probe(&spi->dev, PTR_ERR(irq), "broche %u introuvable\n", broche);
	}

	ret = mesa_irqwatch(md, irq);
	mesa_power_off(md);
	dev_info(&spi->dev, "broche %u après extinction : %d\n", broche, mesa_pin(irq));
	mesa_release(md);
	dev_info(&spi->dev, "capteur éteint, fin (%d)\n", ret);

	return ret ? ret : -ENODEV;	/* essai unique : recharger pour recommencer */
}

static const struct of_device_id mesa_iw_of_match[] = {
	{ .compatible = "biosensor,mesa" },
	{ }
};
MODULE_DEVICE_TABLE(of, mesa_iw_of_match);

static const struct spi_device_id mesa_iw_spi_id[] = {
	{ "mesa" },
	{ }
};
MODULE_DEVICE_TABLE(spi, mesa_iw_spi_id);

static struct spi_driver mesa_iw_driver = {
	.driver = {
		.name = "mesa-irqwatch",
		.of_match_table = mesa_iw_of_match,
	},
	.probe = mesa_iw_probe,
	.id_table = mesa_iw_spi_id,
};
module_spi_driver(mesa_iw_driver);

MODULE_DESCRIPTION("Surveillance de la broche d'interruption du capteur Touch ID (lecture seule)");
MODULE_LICENSE("GPL");
