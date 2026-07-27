// 拍食记路由表 + go_router redirect（无 profile → onboarding）。
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:paishiji/core/app_services.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/image_processor.dart';
import 'package:paishiji/data/providers/vision_provider.dart';

import '../features/barcode/barcode_page.dart';
import '../features/capture/capture_page.dart';
import '../features/diary/diary_page.dart';
import '../features/home/home_page.dart';
import '../features/onboarding/onboarding_flow.dart';
import '../features/recognition/recognition_page.dart';
import '../features/settings/settings_page.dart';

/// 路由路径常量。
class AppRoutes {
  AppRoutes._();
  static const String onboarding = '/onboarding';
  static const String home = '/';
  static const String capture = '/capture';
  static const String recognition = '/recognition';
  static const String barcode = '/barcode';
  static const String diary = '/diary';
  static const String stats = '/stats';
  static const String settings = '/settings';
}

class AppRouter {
  AppRouter(this.services)
    : _router = GoRouter(
        refreshListenable: services,
        redirect: (context, state) {
          final hasProfile = services.hasProfile;
          final onboarding = state.matchedLocation == AppRoutes.onboarding;
          final ready = services.ready;
          if (!ready) return null; // 启动中由 splash 占位
          if (!hasProfile && !onboarding) return AppRoutes.onboarding;
          if (hasProfile && onboarding) return AppRoutes.home;
          return null;
        },
        routes: [
          GoRoute(
            path: AppRoutes.onboarding,
            builder: (context, state) => _OnboardingHost(services: services),
          ),
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: AppRoutes.capture,
            builder: (context, state) => CapturePage(services: services),
          ),
          GoRoute(
            path: AppRoutes.recognition,
            builder: (context, state) {
              final path = state.uri.queryParameters['path'];
              return RecognitionPage(
                imagePath: path ?? '',
                scope: services.data,
                imageProcessor: const DartImageProcessor(),
                // 真实 provider（自定义优先→DashScope→GLM）；无 key 时回退 Mock 不阻塞。
                vision:
                    services.cachedVision ??
                    const VisionChain(primary: MockVisionProvider()),
                estimateProvider: services.cachedEstimate,
              );
            },
          ),
          GoRoute(
            path: AppRoutes.diary,
            builder: (context, state) => DiaryPage(services: services),
          ),
          GoRoute(
            path: AppRoutes.barcode,
            builder: (context, state) => BarcodePage(services: services),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => SettingsPage(services: services),
          ),
        ],
      );

  final AppServices services;
  final GoRouter _router;

  GoRouter get config => _router;
}

/// onboarding 宿主：提交后调用 AppServices.commitProfile。
class _OnboardingHost extends StatelessWidget {
  const _OnboardingHost({required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return OnboardingFlow(
      onFinished: (draft, now) async {
        final result = draft.resolveTargets(now);
        await services.commitProfile(
          ProfilesCompanion.insert(
            gender: draft.gender!.code,
            birthYear: draft.birthYear!,
            heightCm: draft.heightCm,
            weightKg: draft.weightKg,
            activityLevel: draft.activityLevel.code,
            goalType: draft.goalType.code,
            goalRate: draft.goalRate.code,
            targetCalories: result.targetCalories,
            proteinG: result.proteinG,
            carbsG: result.carbsG,
            fatG: result.fatG,
            allergies: const Value('[]'), // TODO(task-2): 接入 allergies 序列化
            updatedAt: now,
          ),
        );
      },
    );
  }
}
