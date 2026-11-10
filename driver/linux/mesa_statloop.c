// SPDX-License-Identifier: GPL-2.0
/*
 * Lecture répétée de l'état du capteur Touch ID « mesa », sans doigt, pour voir
 * si l'état est stable au repos. 2e client de mesa_transport.h (après mesa_probe.c) :
 * montre que la couche transport se réutilise telle quelle.
 *
 * Séquence : allumer, réveil (0x78), puis lire l'état toutes les secondes pendant
 * ~durée secondes, enfin éteindre. Uniquement les trames en clair 0x78 et 0x10.
 * Rien vers le SEP. Aucun code Apple.
 *
 * Ne fait rien sans enable=1. Ne pas charger en même temps que mesa_probe
 * (les deux pilotent le même capteur biosensor,mesa).
 */
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/slab.h>

#include "mesa_transport.h"

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "1 = allumer le capteur et lire son état en boucle (défaut 0 : ne rien faire)");

static unsigned int duree = 30;
module_param(duree, uint, 0444);
MODULE_PARM_DESC(duree, "durée de la boucle en secondes (défaut 30)");

/* Réveil (comme mesa_probe) : le transport ne connaît que l'état générique. */
static const u8 mesa_wake[] = { 0x80, 0x78, 0x00, 0x07, 0x00, 0x00, 0x00 };

static int mesa_statloop(struct mesa_dev *md)
{
	unsigned int i, n = duree;
	int ret, pending, prev = -2, changes = 0;

	ret = mesa_send(md, "réveil", mesa_wake, sizeof(mesa_wake));
	if (ret)
		return ret;

	/* mesa_status journalise déjà l'état RX complet à chaque tour. */
	for (i = 0; i <= n; i++) {
		pending = mesa_status(md);
		if (pending < 0 && pending != -ENOMSG)
			return pending;
		if (pending != prev) {
			if (prev != -2)
				changes++;
			prev = pending;
		}
		if (i < n)
			msleep(1000 - MESA_GAP_MS);	/* ~1 s entre deux lectures */
	}

	dev_info(&md->spi->dev,
		 "RÉSULTAT : %u lectures sur %u s, octets en attente = %d à la fin, %d changement(s) du compteur d'attente\n",
		 n + 1, n, prev, changes);
	return 0;
}

static int mesa_sl_probe(struct spi_device *spi)
{
	struct mesa_dev *md;
	int ret;

	if (!enable)
		return -ENODEV;

	md = devm_kzalloc(&spi->dev, sizeof(*md), GFP_KERNEL);
	if (!md)
		return -ENOMEM;

	ret = mesa_acquire(md, spi);
	if (ret)
		return ret;

	mesa_power_on(md);
	ret = mesa_statloop(md);
	mesa_power_off(md);
	mesa_release(md);
	dev_info(&spi->dev, "capteur éteint, fin (%d)\n", ret);

	return ret ? ret : -ENODEV;	/* essai unique : recharger pour recommencer */
}

static const struct of_device_id mesa_sl_of_match[] = {
	{ .compatible = "biosensor,mesa" },
	{ }
};
MODULE_DEVICE_TABLE(of, mesa_sl_of_match);

static const struct spi_device_id mesa_sl_spi_id[] = {
	{ "mesa" },
	{ }
};
MODULE_DEVICE_TABLE(spi, mesa_sl_spi_id);

static struct spi_driver mesa_sl_driver = {
	.driver = {
		.name = "mesa-statloop",
		.of_match_table = mesa_sl_of_match,
	},
	.probe = mesa_sl_probe,
	.id_table = mesa_sl_spi_id,
};
module_spi_driver(mesa_sl_driver);

MODULE_DESCRIPTION("État du capteur Touch ID lu en boucle au repos (trames en clair)");
MODULE_LICENSE("GPL");
