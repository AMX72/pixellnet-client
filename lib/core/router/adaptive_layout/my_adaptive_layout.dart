import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_route_action.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/features/stats/widget/side_bar_stats_overview.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MyAdaptiveLayout extends HookConsumerWidget {
  const MyAdaptiveLayout({
    super.key,
    required this.navigationShell,
    required this.isMobileBreakpoint,
    required this.showProfilesAction,
  });
  // managed by go router(Shell Route)
  final StatefulNavigationShell navigationShell;
  final bool isMobileBreakpoint;
  final bool showProfilesAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    // focus switch management
    final primaryFocusHash = useState<int?>(null);
    final navScopeNode = useFocusScopeNode();
    useEffect(() {
      bool handler(KeyEvent event) {
        final arrows = isMobileBreakpoint ? KeyboardConst.verticalArrows : KeyboardConst.horizontalArrows;
        if (!arrows.contains(event.logicalKey)) return false;
        if (event is KeyDownEvent) {
          primaryFocusHash.value = FocusManager.instance.primaryFocus.hashCode;
        } else {
          // focus node does not change => true.
          if (primaryFocusHash.value == FocusManager.instance.primaryFocus.hashCode) {
            if (branchesScope.values.any((node) => node.hasFocus)) {
              navScopeNode.requestFocus();
            } else if (navScopeNode.hasFocus) {
              branchesScope[getNameOfBranch(isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex)]
                  ?.requestFocus();
            }
          }
        }
        return true;
      }

      HardwareKeyboard.instance.addHandler(handler);
      return () {
        HardwareKeyboard.instance.removeHandler(handler);
      };
    }, [isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex]);
    // Sprint 3 sidebar mapping. Видимые пункты: 0=Главная, 1=Настройки.
    // Реальные go_router branches: 0=Home, 1=Profiles, 2=Settings, 3=Logs, 4=About.
    // Юзер видит только 2, но branches все ещё активны для deep-link/dev-menu.
    final visibleSelectedIndex = navigationShell.currentIndex == 0 ? 0 : 1;
    return Material(
      child: Scaffold(
        body: isMobileBreakpoint
            ? navigationShell
            : Row(
                children: [
                  FocusScope(
                    node: navScopeNode,
                    child: NavigationRail(
                      extended: Breakpoint(context).isDesktop(),
                      destinations: _navRailDests(_actions(t)),
                      selectedIndex: visibleSelectedIndex,
                      onDestinationSelected: (visibleIndex) => _onTap(context, _mapVisibleToBranch(visibleIndex)),
                      trailing: null,
                    ),
                  ),
                  Expanded(child: navigationShell),
                ],
              ),
        bottomNavigationBar: isMobileBreakpoint
            ? FocusScope(
                node: navScopeNode,
                child: NavigationBar(
                  selectedIndex: visibleSelectedIndex,
                  destinations: _navDests(_actions(t)),
                  onDestinationSelected: (visibleIndex) => _onTap(context, _mapVisibleToBranch(visibleIndex)),
                ),
              )
            : null,
      ),
    );
  }

  // shell route action onTap
  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  /// Маппинг видимого индекса → реальный go_router branch index.
  /// UI: 0=Главная, 1=Настройки. Branches: 0=Home, 1=Profiles, 2=Settings.
  int _mapVisibleToBranch(int visibleIndex) => visibleIndex == 0 ? 0 : 2;

  /// Sprint 3: sidebar сокращён до 2 пунктов (Главная + Настройки).
  /// «Профили», «Логи», «О программе» вынесены в Настройки → Дополнительно
  /// и dev-menu (5-tap по версии). Один юзер = один ключ → отдельный «Профили» не нужен.
  List<ShellRouteAction> _actions(Translations t) => [
    ShellRouteAction(Icons.power_settings_new_rounded, t.pages.home.title),
    ShellRouteAction(Icons.settings_rounded, t.pages.settings.title),
  ];

  List<NavigationDestination> _navDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationDestination(icon: Icon(e.icon), label: e.title)).toList();
  List<NavigationRailDestination> _navRailDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationRailDestination(icon: Icon(e.icon), label: Text(e.title))).toList();
}
