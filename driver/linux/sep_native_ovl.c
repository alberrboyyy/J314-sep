// SPDX-License-Identifier: GPL-2.0
/*
 * sep_native_ovl : ajoute à chaud le nœud distinct « j314c,sep-native » (sep-native.dtbo dans /lib/firmware,
 * source sep-native-overlay.dts) auquel se lie le pilote Rust sep_native.ko. Calqué sur mesa_ovl.c.
 *
 * Ne parle à AUCUN matériel et n'envoie RIEN au SEP : il ne fait que décrire le matériel. Le nœud d'origine
 * /soc/sep@396400000 (compatible "apple,sep") reste "disabled" : le pilote intégré apple_sep ne se lie pas.
 * Seule retouche, en mémoire : si le nœud sep n'a pas de phandle (personne ne le référence), on lui en donne
 * un (max + 1), comme mesa_ovl.c le fait pour ps_spi2 ; rien n'est écrit sur disque, un reboot l'efface.
 *
 * FAIL-CLOSED : refus (-ENODEV) si la région « sepfw » est absente. m1n1 ne la crée (et ne copie les
 * manifestes) que si le DT de boot porte l'alias « sep » (m1n1 src/kboot.c dt_set_sep) ; au boot normal
 * d'ALARM (2026-11-22) il n'y a ni alias ni région : ce module refuse alors de se charger.
 *
 * Les marqueurs 0xdeadbe01..06 du dtbo sont remplacés par les valeurs du DT vivant (voir le .dts).
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/firmware.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/unaligned.h>

#define SEP_PATH	"/soc/sep@396400000"
#define NATIVE_COMPAT	"j314c,sep-native"
#define DTBO_NAME	"sep-native.dtbo"

enum { M_MBOX, M_DART, M_SID, M_PD, M_FW, M_SEP, M_COUNT };
static const u32 marks[M_COUNT] = {
	0xdeadbe01, 0xdeadbe02, 0xdeadbe03, 0xdeadbe04, 0xdeadbe05, 0xdeadbe06,
};

static int ovcs_id;

/* Lit exactement n cellules u32 de la propriété (refus si la longueur diffère). */
static int read_cells(struct device_node *np, const char *prop, u32 *out, int n)
{
	int cnt = of_property_count_u32_elems(np, prop);

	if (cnt != n) {
		pr_err("sep_native_ovl: %s : %d cellules (%d attendues)\n", prop, cnt, n);
		return -EINVAL;
	}
	return of_property_read_u32_array(np, prop, out, n);
}

/* Vérifie que le phandle ph désigne un nœud compatible compat. */
static int check_target(u32 ph, const char *what, const char *compat)
{
	struct device_node *t = of_find_node_by_phandle(ph);
	int ok;

	if (!t) {
		pr_err("sep_native_ovl: %s : phandle %#x introuvable\n", what, ph);
		return -ENODEV;
	}
	ok = of_device_is_compatible(t, compat);
	pr_info("sep_native_ovl: %s = %#x -> %pOF%s\n", what, ph, t, ok ? "" : " (compatible inattendu)");
	of_node_put(t);
	return ok ? 0 : -ENODEV;
}

/* Contrôles de la région sepfw et des manifestes ; renvoie le phandle de sep-firmware. */
static int check_sepfw(struct device_node *sep, u32 *fw_ph)
{
	struct device_node *fw;
	struct resource r;
	int idx, ret;

	idx = of_property_match_string(sep, "memory-region-names", "sepfw");
	if (idx < 0) {
		pr_err("sep_native_ovl: pas de région « sepfw » sur %s : m1n1 n'a pas vu d'alias « sep » dans le DT de ce boot (aucun firmware SEP réservé). Rien à faire, refus.\n",
		       SEP_PATH);
		return -ENODEV;
	}
	fw = of_parse_phandle(sep, "memory-region", idx);
	if (!fw) {
		pr_err("sep_native_ovl: memory-region[%d] introuvable\n", idx);
		return -ENODEV;
	}
	ret = -ENODEV;
	if (!of_device_is_compatible(fw, "apple,asc-mem") || !of_node_name_eq(fw, "sep-firmware")) {
		pr_err("sep_native_ovl: région %pOF inattendue (sep-firmware / apple,asc-mem attendus)\n", fw);
		goto out;
	}
	if (of_address_to_resource(fw, 0, &r)) {
		pr_err("sep_native_ovl: %pOF sans reg\n", fw);
		goto out;
	}
	if (!of_find_property(sep, "local-policy-manifest", NULL) ||
	    !of_find_property(sep, "iboot-manifest", NULL)) {
		pr_err("sep_native_ovl: manifestes absents de %s\n", SEP_PATH);
		goto out;
	}
	if (!fw->phandle) {
		pr_err("sep_native_ovl: %pOF sans phandle\n", fw);
		goto out;
	}
	*fw_ph = fw->phandle;
	pr_info("sep_native_ovl: sepfw = %pOF %pR, phandle %#x ; manifestes présents\n", fw, &r, *fw_ph);
	ret = 0;
out:
	of_node_put(fw);
	return ret;
}

static int patch_and_apply(const u32 *val)
{
	const struct firmware *fw;
	u8 *blob;
	size_t size, i;
	int ret, m, n[M_COUNT] = { 0 };

	ret = request_firmware(&fw, DTBO_NAME, NULL);
	if (ret) {
		pr_err("sep_native_ovl: /lib/firmware/%s introuvable (%d)\n", DTBO_NAME, ret);
		return ret;
	}
	size = fw->size;
	blob = kmemdup(fw->data, size, GFP_KERNEL);
	release_firmware(fw);
	if (!blob)
		return -ENOMEM;
	/* Les cellules d'un FDT sont alignées sur 4 octets. */
	for (i = 0; i + 4 <= size; i += 4)
		for (m = 0; m < M_COUNT; m++)
			if (get_unaligned_be32(blob + i) == marks[m]) {
				put_unaligned_be32(val[m], blob + i);
				n[m]++;
			}
	for (m = 0; m < M_COUNT; m++)
		if (n[m] != 1) {
			pr_err("sep_native_ovl: marqueur %#x trouvé %d fois (1 attendu)\n", marks[m], n[m]);
			kfree(blob);
			return -EINVAL;
		}
	ret = of_overlay_fdt_apply(blob, size, &ovcs_id, NULL);
	kfree(blob);
	pr_info("sep_native_ovl: overlay appliqué, ret=%d id=%d\n", ret, ovcs_id);
	if (ret && ovcs_id)
		of_overlay_remove(&ovcs_id);
	return ret;
}

static int __init sep_native_ovl_init(void)
{
	struct device_node *sep, *np;
	const char *mbox_name;
	u32 val[M_COUNT], iommu[2];
	phandle max = 0;
	int ret;

	np = of_find_compatible_node(NULL, NULL, NATIVE_COMPAT);
	if (np) {
		pr_err("sep_native_ovl: %pOF existe déjà, rien à faire\n", np);
		of_node_put(np);
		return -EEXIST;
	}
	sep = of_find_node_by_path(SEP_PATH);
	if (!sep || !of_device_is_compatible(sep, "apple,sep")) {
		pr_err("sep_native_ovl: %s absent ou pas apple,sep\n", SEP_PATH);
		ret = -ENODEV;
		goto out;
	}
	if (of_device_is_available(sep)) {
		/* apple_sep (CONFIG_APPLE_SEP=y) s'y lie et boote le SEP : jamais deux clients de sep_mbox. */
		pr_err("sep_native_ovl: %s n'est PAS disabled (apple_sep peut s'y lier) : refus\n", SEP_PATH);
		ret = -EBUSY;
		goto out;
	}
	ret = check_sepfw(sep, &val[M_FW]);
	if (ret)
		goto out;

	ret = read_cells(sep, "mboxes", &val[M_MBOX], 1);
	if (ret)
		goto out;
	if (of_property_read_string(sep, "mbox-names", &mbox_name) || strcmp(mbox_name, "mbox")) {
		pr_err("sep_native_ovl: mbox-names inattendu\n");
		ret = -ENODEV;
		goto out;
	}
	ret = read_cells(sep, "iommus", iommu, 2);
	if (ret)
		goto out;
	val[M_DART] = iommu[0];
	val[M_SID] = iommu[1];
	ret = read_cells(sep, "power-domains", &val[M_PD], 1);
	if (ret)
		goto out;

	ret = check_target(val[M_MBOX], "mboxes", "apple,asc-mailbox-v4");
	if (!ret)
		ret = check_target(val[M_DART], "iommus", "apple,t6000-dart");
	if (!ret)
		ret = check_target(val[M_PD], "power-domains", "apple,pmgr-pwrstate");
	if (ret)
		goto out;
	pr_info("sep_native_ovl: stream id DART = %u\n", val[M_SID]);

	if (!sep->phandle) {
		for (np = of_find_all_nodes(NULL); np; np = of_find_all_nodes(np))
			if (np->phandle != 0xffffffff && np->phandle > max)
				max = np->phandle;
		sep->phandle = max + 1;
		pr_info("sep_native_ovl: phandle %#x donné (en mémoire) à %s\n", sep->phandle, SEP_PATH);
	}
	val[M_SEP] = sep->phandle;

	ret = patch_and_apply(val);
out:
	of_node_put(sep);
	return ret;
}

static void __exit sep_native_ovl_exit(void)
{
	struct device_node *np;
	struct platform_device *pdev = NULL;
	bool bound = false;

	if (!ovcs_id)
		return;
	np = of_find_compatible_node(NULL, NULL, NATIVE_COMPAT);
	if (np) {
		pdev = of_find_device_by_node(np);
		of_node_put(np);
	}
	if (pdev) {
		bound = pdev->dev.driver != NULL;
		put_device(&pdev->dev);
	}
	if (bound) {
		/*
		 * Retirer l'overlay supprimerait le device sous sep_native (unbind). On le laisse en place jusqu'au
		 * reboot : décharger d'abord sep_native (possible seulement s'il n'a rien envoyé au SEP).
		 */
		pr_warn("sep_native_ovl: sep_native est lié au nœud : overlay LAISSÉ en place (id=%d) jusqu'au reboot\n",
			ovcs_id);
		return;
	}
	pr_info("sep_native_ovl: retrait de l'overlay, ret=%d\n", of_overlay_remove(&ovcs_id));
}

module_init(sep_native_ovl_init);
module_exit(sep_native_ovl_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Ajout à chaud du nœud j314c,sep-native pour sep_native.ko (n'envoie rien au SEP)");
