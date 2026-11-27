import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import 'assistant_chat_screen.dart';

/// 用講的改訂位設定（ops 0147，公版階段 2 第 7 步；只有老闆）。畫面跟排班的共用（assistant_chat_screen.dart）。
class BookingAssistantScreen extends StatelessWidget {
  const BookingAssistantScreen({super.key, required this.membership});
  final Membership membership;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    final store = membership.storeId;
    return AssistantChatScreen(
      config: AssistantConfig(
        title: '用講的改訂位設定',
        examples: const ['這週六包場，不開放線上訂位', '英文介紹改得更有畫面一點', '加開日文版', '低消改成每人 700'],
        canChange: '目前能改：訂位頁的大標、介紹、外語地址、低消、開哪些語言，還有某一天整天不開放。',
        hint: '例如：12/24 包場不開放',
        applied: '改好了，客人重新整理訂位頁就看得到',
        ask: (m, h) => repo.askBookingAssistant(store, m, h),
        apply: (r, c) => repo.applyBookingAssist(store, r, c),
        history: () => repo.bookingAssistHistory(store),
        undo: repo.undoBookingAssist,
      ),
    );
  }
}
