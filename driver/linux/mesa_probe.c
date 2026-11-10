// SPDX-License-Identifier: GPL-2.0
/*
 * « Bonjour » au capteur Touch ID (ADT "biosensor,mesa", bus spi2 du j314c) depuis Linux.
 *
 * Premier client de la couche transport (mesa_transport.h) : réveil, état, identité,
 * lecture de l'identité, état, extinction. Uniquement les 4 trames en clair
 * (0x78, 0x10, 0x70, 0x13). Aucune trame chiffrée, rien vers le SEP.
 *
 * La séquence a été vérifiée 2 fois depuis m1n1 (tools/mesa_hello.sh, docs/journal.md
 * MESA-HELLO) et une fois depuis Linux (LINUX-HELLO).
 *
 * Ne fait rien sans le paramètre enable=1. Écrit à partir de docs/ et de l'API
 * publique Linux ; aucun code Apple.
 */
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/slab.h>

#include "mesa_transport.h"

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "1 = allumer le capteur et lire son identité (défaut 0 : ne rien faire)");

#define MESA_ID_LEN	0x1b

/* Trames propres au « bonjour » (le transport ne connaît que l'état générique). */
static const u8 mesa_wake[]    = { 0x80, 0x78, 0x00, 0x07, 0x00, 0x00, 0x00 };
static const u8 mesa_get_id[]  = { 0x80, 0x70, 0x00, 0x07, 0x00, 0x00, 0x00 };
static const u8 mesa_read_id[] = { 0x80, 0x13, 0x00, 0x0b, 0x00, 0x00, 0x00, MESA_ID_LEN, 0x00, 0x00, 0x00 };
/* Identité lue sous macOS (C18, C19) et depuis m1n1 (MESA-HELLO, 2 essais). */
static const u8 mesa_id_expected[MESA_ID_LEN] = {
	0x80, 0xd4, 0x00, 0x1b, 0x00, 0x00, 0x00, 0x00, 0x70, 0x02, 0x19, 0xc0, 0x5c, 0x0f,
	0xd2, 0xaa, 0x34, 0x9a, 0x81, 0xc7, 0x6e, 0x03, 0x02, 0x00, 0xd8, 0x75, 0x76,
};

static int mesa_hello(struct mesa_dev *md)
{
	int ret, pending;

	ret = mesa_send(md, "réveil", mesa_wake, sizeof(mesa_wake));
	if (ret)
		return ret;
	mesa_wait_ready(md);		/* réactif : attendre la montée « donnée prête » plutôt qu'une pause fixe */
	ret = mesa_status(md);
	if (ret < 0 && ret != -ENOMSG)
		return ret;
	ret = mesa_send(md, "identité", mesa_get_id, sizeof(mesa_get_id));
	if (ret)
		return ret;
	mesa_wait_ready(md);		/* la réponse d'identité remonte la broche (vérifié 2026-11-10) */
	pending = mesa_status(md);
	if (pending < 0 && pending != -ENOMSG)
		return pending;
	dev_info(&md->spi->dev, "réponse en attente : %d octets\n", pending < 0 ? 0 : pending);

	if (pending != MESA_ID_LEN) {
		dev_warn(&md->spi->dev, "RÉSULTAT : pas d'identité lue (le capteur n'annonce pas 0x1b octets)\n");
		return 0;
	}

	ret = mesa_send(md, "demande", mesa_read_id, sizeof(mesa_read_id));
	if (ret)
		return ret;
	ret = mesa_read(md, "réponse", MESA_ID_LEN);
	if (ret)
		return ret;
	if (!memcmp(md->rx, mesa_id_expected, MESA_ID_LEN))
		dev_info(&md->spi->dev, "RÉSULTAT : IDENTITÉ IDENTIQUE à celle lue sous macOS et depuis m1n1\n");
	else
		dev_warn(&md->spi->dev, "RÉSULTAT : réponse différente de l'identité attendue\n");

	ret = mesa_status(md);
	return ret < 0 && ret != -ENOMSG ? ret : 0;
}

static int mesa_probe(struct spi_device *spi)
{
	struct mesa_dev *md;
	int ret;

	if (!enable)
		return -ENODEV;		/* défaut : aucune action, aucune écriture */

	md = devm_kzalloc(&spi->dev, sizeof(*md), GFP_KERNEL);
	if (!md)
		return -ENOMEM;

	ret = mesa_acquire(md, spi);
	if (ret)
		return ret;

	mesa_power_on(md);
	ret = mesa_hello(md);
	mesa_power_off(md);
	mesa_release(md);
	dev_info(&spi->dev, "capteur éteint, fin (%d)\n", ret);

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
