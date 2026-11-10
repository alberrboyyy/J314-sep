// SPDX-License-Identifier: GPL-2.0
/*
 * mesa_ovl : ajoute à chaud le nœud spi2 + capteur (mesa-spi2.dtbo dans /lib/firmware) au device tree vivant.
 * Linux de test uniquement. Rien d'écrit sur disque ni dans la chaîne de démarrage ; rmmod ou reboot annule.
 * Le nœud ps_spi2 du DT vivant n'a pas de phandle (personne ne le référence) : on lui en donne un en mémoire
 * (max + 1) et on remplace le marqueur 0xdeadbeef du .dtbo par cette valeur.
 * N'envoie rien au capteur ni au SEP : il ne fait que décrire le matériel ; spi-apple initialise alors spi2.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/firmware.h>
#include <linux/slab.h>
#include <linux/unaligned.h>

#define PS_PATH "/soc/power-management@28e580000/power-controller@200"
#define MARK 0xdeadbeef

static int ovcs_id;

static int __init mesa_ovl_init(void)
{
	const struct firmware *fw;
	struct device_node *ps, *np;
	const char *label;
	phandle max = 0;
	u8 *blob;
	size_t size;
	int ret, i, n = 0;

	if (of_find_node_by_path("/soc/spi@39b108000")) {
		pr_err("mesa_ovl: spi2 existe déjà, rien à faire\n");
		return -EEXIST;
	}
	ps = of_find_node_by_path(PS_PATH);
	if (!ps || of_property_read_string(ps, "label", &label) || strcmp(label, "spi2")) {
		pr_err("mesa_ovl: nœud ps_spi2 introuvable ou inattendu\n");
		return -ENODEV;
	}
	if (!ps->phandle) {
		for (np = of_find_all_nodes(NULL); np; np = of_find_all_nodes(np))
			if (np->phandle != 0xffffffff && np->phandle > max)
				max = np->phandle;
		ps->phandle = max + 1;
	}
	pr_info("mesa_ovl: ps_spi2 phandle = %#x\n", ps->phandle);

	ret = request_firmware(&fw, "mesa-spi2.dtbo", NULL);
	if (ret)
		return ret;
	size = fw->size;
	blob = kmemdup(fw->data, size, GFP_KERNEL);
	release_firmware(fw);
	if (!blob)
		return -ENOMEM;
	for (i = 0; i + 4 <= size; i += 4)
		if (get_unaligned_be32(blob + i) == MARK) {
			put_unaligned_be32(ps->phandle, blob + i);
			n++;
		}
	if (n != 1) {
		pr_err("mesa_ovl: %d marqueurs dans le dtbo (1 attendu)\n", n);
		kfree(blob);
		return -EINVAL;
	}
	ret = of_overlay_fdt_apply(blob, size, &ovcs_id, NULL);
	kfree(blob);
	pr_info("mesa_ovl: overlay appliqué, ret=%d id=%d\n", ret, ovcs_id);
	if (ret && ovcs_id)
		of_overlay_remove(&ovcs_id);
	return ret;
}

static void __exit mesa_ovl_exit(void)
{
	if (ovcs_id)
		pr_info("mesa_ovl: retrait de l'overlay, ret=%d\n", of_overlay_remove(&ovcs_id));
}

module_init(mesa_ovl_init);
module_exit(mesa_ovl_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Ajout à chaud de spi2 + capteur Touch ID (Linux de test)");
