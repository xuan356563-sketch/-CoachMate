import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/core/constants/app_brand.dart';

void main() {
  group('AppBrand', () {
    test('品牌名称与口号固定为已确认值', () {
      expect(AppBrand.displayName, '练搭 CoachMate');
      expect(AppBrand.shortName, '练搭');
      expect(AppBrand.englishName, 'CoachMate');
      expect(AppBrand.tagline, '练，有人陪。');
    });

    test('Web 描述体现本地优先与长期陪伴定位', () {
      expect(
        AppBrand.webDescription,
        '练搭 CoachMate：本地优先的 AI Coach agent 与运动搭子，陪你长期训练。',
      );
    });

    test('Flutter 用户可见展示面不再保留旧品牌文本', () {
      const List<String> sourcePaths = <String>[
        'lib/app/trainflow_app.dart',
        'lib/app/startup/local_storage_recovery_page.dart',
        'lib/core/widgets/trainmate_action_character.dart',
        'lib/core/widgets/trainmate_branding.dart',
        'lib/features/auth/data/authenticated_api_client.dart',
        'lib/features/auth/presentation/auth_pages.dart',
        'lib/features/companion/application/companion_controller.dart',
        'lib/features/companion/application/companion_notification_scheduler.dart',
        'lib/features/data_center/data_center_page.dart',
        'lib/features/first_run_onboarding/presentation/first_run_pages.dart',
        'lib/features/training_plan/plan_generation_page.dart',
        'lib/features/workout_player/application/workout_player_assist_controller.dart',
        'lib/services/four_week_plan_generator.dart',
        'lib/services/system_training_notification_service.dart',
      ];
      final RegExp oldQuotedBrand =
          RegExp(r'''['"][^'"\r\n]*TrainMate[^'"\r\n]*['"]''');

      for (final String sourcePath in sourcePaths) {
        final String source = File(sourcePath).readAsStringSync();
        expect(source, isNot(contains('智练 TrainMate')), reason: sourcePath);
        expect(oldQuotedBrand.hasMatch(source), isFalse, reason: sourcePath);
      }
    });

    test('iOS、Android、Web 与 StoreKit 统一展示新品牌并保持兼容标识', () {
      final String androidManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final String androidGradle = File(
        'android/app/build.gradle.kts',
      ).readAsStringSync();
      final Map<String, dynamic> webManifest = jsonDecode(
        File('web/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final String webIndex = File('web/index.html').readAsStringSync();
      final Map<String, dynamic> storeKit = jsonDecode(
        File('ios/StoreKit/TrainMate.storekit').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Map<String, dynamic> subscriptionGroup =
          ((storeKit['subscriptionGroups'] as List<dynamic>).single
              as Map<String, dynamic>);

      expect(
          androidManifest, contains('android:label="${AppBrand.displayName}"'));
      expect(androidGradle, contains('namespace = "com.zhilian.trainmate"'));
      expect(
        androidGradle,
        contains('applicationId = "com.zhilian.trainmate"'),
      );
      expect(webManifest['name'], AppBrand.displayName);
      expect(webManifest['short_name'], AppBrand.shortName);
      expect(webManifest['description'], AppBrand.webDescription);
      expect(
        webIndex,
        contains(
            '<meta name="description" content="${AppBrand.webDescription}">'),
      );
      expect(
        webIndex,
        contains(
          '<meta name="apple-mobile-web-app-title" content="${AppBrand.displayName}">',
        ),
      );
      expect(webIndex, contains('<title>${AppBrand.displayName}</title>'));
      expect(subscriptionGroup['name'], '${AppBrand.englishName} Membership');
      expect(
        File('ios/StoreKit/TrainMate.storekit').readAsStringSync(),
        contains('"displayName" : "${AppBrand.displayName} 会员"'),
      );
      expect(
        File('ios/StoreKit/TrainMate.storekit').readAsStringSync(),
        contains('"productID" : "com.zhilian.trainmate.membership.monthly"'),
      );
      expect(
        File('ios/StoreKit/TrainMate.storekit').readAsStringSync(),
        contains('"referenceName" : "TrainMate Monthly"'),
      );
    });
  });
}
