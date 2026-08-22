import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_access_filter.dart';

void main() {
  group('matchesAdminAccessFilter', () {
    test('all keeps every user', () {
      expect(
        matchesAdminAccessFilter(
          filter: AdminAccessFilter.all,
          hasAccess: false,
          hasRole: false,
        ),
        isTrue,
      );
    });

    test('enabled and disabled separate visibility', () {
      expect(
        matchesAdminAccessFilter(
          filter: AdminAccessFilter.enabled,
          hasAccess: true,
          hasRole: false,
        ),
        isTrue,
      );
      expect(
        matchesAdminAccessFilter(
          filter: AdminAccessFilter.disabled,
          hasAccess: true,
          hasRole: false,
        ),
        isFalse,
      );
    });

    test('role filters only include users with module access', () {
      expect(
        matchesAdminAccessFilter(
          filter: AdminAccessFilter.enabledWithRole,
          hasAccess: true,
          hasRole: true,
        ),
        isTrue,
      );
      expect(
        matchesAdminAccessFilter(
          filter: AdminAccessFilter.enabledWithoutRole,
          hasAccess: true,
          hasRole: false,
        ),
        isTrue,
      );
      expect(
        matchesAdminAccessFilter(
          filter: AdminAccessFilter.enabledWithoutRole,
          hasAccess: false,
          hasRole: false,
        ),
        isFalse,
      );
    });
  });
}
