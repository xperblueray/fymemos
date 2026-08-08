import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fymemos/config/refena.dart';
import 'package:fymemos/data/services/shared_preference_service.dart';
import 'package:fymemos/utils/result.dart';
import 'package:fymemos/ui/core/theme/dynamic_colors.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Global notifier that GoRouter.refreshListenable listens to.
/// Pre-loaded synchronously in preinit so redirect can read it.
final loginNotifier = ValueNotifier<bool?>(null); // null = not checked yet

Future<RefenaContainer> preinit(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dynamicColors = await getDynamicColors();

  // Pre-check login state so GoRouter redirect can use it synchronously
  final sp = SharedPreferencesService.instance;
  final (baseUrlResult, tokenResult) =
      await (sp.fetchBaseUrl(), sp.fetchToken()).wait;
  final isLoggedIn =
      baseUrlResult is Ok && tokenResult is Ok &&
      (baseUrlResult as Ok<String?>).value != null &&
      (tokenResult as Ok<String?>).value != null;
  loginNotifier.value = isLoggedIn;

  final container = RefenaContainer(
    observers: kDebugMode ? [CustomRefenaObserver()] : [],
    overrides: [dynamicColorsProvider.overrideWithValue(dynamicColors)],
  );

  return container;
}
