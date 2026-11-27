import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import 'assistant_chat_screen.dart';

/// 「用講的改排班設定」的入口只在公版那一份 App 出現（ops 0154；隱城／小城外這一份畫面不變）
const shiftAssistantVisible = AppConfig.selfSignup;

/// 用講的改排班設定（ops 0154，智慧排班公版化；老闆、店長）。畫面跟訂位的共用（assistant_chat_screen.dart）。
/// AI 只會提出「改前 → 改後」，按確認才改；能改每天要幾人、某一天要幾人、填班截止日、盡量不連上、指休規則、個人的排班條件。
class ShiftAssistantScreen extends StatelessWidget {
  const ShiftAssistantScreen({super.key, required this.membership});
  final Membership membership;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    final store = membership.storeId;
    return AssistantChatScreen(
      config: AssistantConfig(
        title: '用講的改排班設定',
        examples: const ['週五週六要 5 個人', '聖誕節那天要 6 個人', '同一天最多 2 位指休', '每月 25 號前填好班'],
        canChange: '目前能改：每天要幾人、某一天要幾人、填班截止日、盡量不連上幾天、指休規則，還有每個人的休幾天、最多最少上幾天、固定不排的星期。',
        hint: '例如：週五要 5 個人',
        applied: '改好了，下次自動排班就照新的設定',
        ask: (m, h) => repo.askShiftAssistant(store, m, h),
        apply: (r, c) => repo.applyShiftAssist(store, r, c),
        history: () => repo.shiftAssistHistory(store),
        undo: repo.undoShiftAssist,
      ),
    );
  }
}
