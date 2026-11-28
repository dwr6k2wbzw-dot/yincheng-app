import 'package:flutter/material.dart';

/// 損益設定的業態範本（ops 0169，只有公版）：自己開的新店照業態帶一組常用會計科目，之後老闆自己改。
/// 正式版的內容一律讀資料庫 public.pl_template_list()（app.pl_template）；
/// 這裡的 [demoPlTemplates] 只給示範版用，跟資料庫那份一樣，改範本要兩邊一起改。
class PlTemplateAccount {
  final String name;
  final String category; // rent / payroll / misc
  final String? autoKind; // payroll_base / rent_base / card_fee / purchase_misc
  const PlTemplateAccount(this.name, this.category, [this.autoKind]);
}

class PlTemplate {
  final String kind;
  final String label;
  final String note;
  final List<PlTemplateAccount> accounts;
  const PlTemplate({
    required this.kind,
    required this.label,
    required this.note,
    required this.accounts,
  });

  factory PlTemplate.fromJson(Map<String, dynamic> j) => PlTemplate(
    kind: j['kind'] as String,
    label: j['label'] as String? ?? j['kind'] as String,
    note: j['note'] as String? ?? '',
    accounts: [
      for (final a in (j['accounts'] as List? ?? const []))
        PlTemplateAccount(
          (a as List)[0] as String,
          a[1] as String,
          a.length > 2 ? a[2] as String? : null,
        ),
    ],
  );

  IconData get icon => switch (kind) {
    'bar' => Icons.local_bar_outlined,
    'cafe' => Icons.local_cafe_outlined,
    'restaurant' => Icons.restaurant_outlined,
    _ => Icons.storefront_outlined,
  };

  /// 一句話摘要：「16 個科目・人事 3・租金 1・雜項 12」
  String get summary {
    int n(String c) => accounts.where((a) => a.category == c).length;
    final parts = [
      for (final c in const ['payroll', 'rent', 'misc'])
        if (n(c) > 0) '${plCategoryLabels[c]} ${n(c)}',
    ];
    return ['${accounts.length} 個科目', ...parts].join('・');
  }
}

/// 自動帶入的那幾筆（照 ops 0142 的 auto_kind）：畫面上的名稱、要放在哪一大項
const plAutoKinds = <String, (String, String)>{
  'payroll_base': ('人事基底（總覽填的人事金額）', 'payroll'),
  'rent_base': ('租金基底（總覽填的租金金額）', 'rent'),
  'card_fee': ('刷卡手續費（自動算）', 'misc'),
  'purchase_misc': ('進貨的雜項類', 'misc'),
};

const plCategoryLabels = {'payroll': '人事', 'rent': '租金', 'misc': '雜項'};

const _base = [
  PlTemplateAccount('薪資支出', 'payroll', 'payroll_base'),
  PlTemplateAccount('保險費-勞健保+退休金', 'payroll'),
  PlTemplateAccount('職工福利', 'payroll'),
  PlTemplateAccount('租金支出', 'rent', 'rent_base'),
];

/// 示範版用（同資料庫 app.pl_template；改要兩邊一起改）
const demoPlTemplates = <PlTemplate>[
  PlTemplate(
    kind: 'bar',
    label: '酒吧',
    note: '多一個演出及活動費（DJ、樂手、包場活動）',
    accounts: [
      ..._base,
      PlTemplateAccount('水電瓦斯費', 'misc'),
      PlTemplateAccount('郵電費', 'misc'),
      PlTemplateAccount('手續費', 'misc', 'card_fee'),
      PlTemplateAccount('其他費用-雜項', 'misc', 'purchase_misc'),
      PlTemplateAccount('其他費用-垃圾清運費', 'misc'),
      PlTemplateAccount('廣告費', 'misc'),
      PlTemplateAccount('演出及活動費', 'misc'),
      PlTemplateAccount('修繕費', 'misc'),
      PlTemplateAccount('保險費', 'misc'),
      PlTemplateAccount('系統及軟體月費', 'misc'),
      PlTemplateAccount('記帳及會計師費', 'misc'),
      PlTemplateAccount('營業稅', 'misc'),
    ],
  ),
  PlTemplate(
    kind: 'cafe',
    label: '咖啡廳',
    note: '多一個外送平台抽成',
    accounts: [
      ..._base,
      PlTemplateAccount('水電瓦斯費', 'misc'),
      PlTemplateAccount('郵電費', 'misc'),
      PlTemplateAccount('手續費', 'misc', 'card_fee'),
      PlTemplateAccount('外送平台抽成', 'misc'),
      PlTemplateAccount('其他費用-雜項', 'misc', 'purchase_misc'),
      PlTemplateAccount('其他費用-垃圾清運費', 'misc'),
      PlTemplateAccount('廣告費', 'misc'),
      PlTemplateAccount('修繕費', 'misc'),
      PlTemplateAccount('保險費', 'misc'),
      PlTemplateAccount('系統及軟體月費', 'misc'),
      PlTemplateAccount('記帳及會計師費', 'misc'),
      PlTemplateAccount('營業稅', 'misc'),
    ],
  ),
  PlTemplate(
    kind: 'restaurant',
    label: '餐廳',
    note: '水電、瓦斯分開，多外送平台抽成、清潔消毒費',
    accounts: [
      ..._base,
      PlTemplateAccount('水電費', 'misc'),
      PlTemplateAccount('瓦斯費', 'misc'),
      PlTemplateAccount('郵電費', 'misc'),
      PlTemplateAccount('手續費', 'misc', 'card_fee'),
      PlTemplateAccount('外送平台抽成', 'misc'),
      PlTemplateAccount('其他費用-雜項', 'misc', 'purchase_misc'),
      PlTemplateAccount('其他費用-垃圾清運費', 'misc'),
      PlTemplateAccount('清潔消毒費', 'misc'),
      PlTemplateAccount('廣告費', 'misc'),
      PlTemplateAccount('修繕費', 'misc'),
      PlTemplateAccount('保險費', 'misc'),
      PlTemplateAccount('系統及軟體月費', 'misc'),
      PlTemplateAccount('記帳及會計師費', 'misc'),
      PlTemplateAccount('營業稅', 'misc'),
    ],
  ),
  PlTemplate(
    kind: 'other',
    label: '其他',
    note: '先放最基本的，之後自己加',
    accounts: [
      PlTemplateAccount('薪資支出', 'payroll', 'payroll_base'),
      PlTemplateAccount('保險費-勞健保+退休金', 'payroll'),
      PlTemplateAccount('租金支出', 'rent', 'rent_base'),
      PlTemplateAccount('水電瓦斯費', 'misc'),
      PlTemplateAccount('郵電費', 'misc'),
      PlTemplateAccount('手續費', 'misc', 'card_fee'),
      PlTemplateAccount('其他費用-雜項', 'misc', 'purchase_misc'),
      PlTemplateAccount('記帳及會計師費', 'misc'),
      PlTemplateAccount('營業稅', 'misc'),
    ],
  ),
];
