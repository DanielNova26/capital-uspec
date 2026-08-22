enum AdminAccessFilter {
  all,
  enabled,
  disabled,
  enabledWithRole,
  enabledWithoutRole,
}

bool matchesAdminAccessFilter({
  required AdminAccessFilter filter,
  required bool hasAccess,
  required bool hasRole,
}) {
  switch (filter) {
    case AdminAccessFilter.all:
      return true;
    case AdminAccessFilter.enabled:
      return hasAccess;
    case AdminAccessFilter.disabled:
      return !hasAccess;
    case AdminAccessFilter.enabledWithRole:
      return hasAccess && hasRole;
    case AdminAccessFilter.enabledWithoutRole:
      return hasAccess && !hasRole;
  }
}
