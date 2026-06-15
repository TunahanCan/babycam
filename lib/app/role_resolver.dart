import 'app_role.dart';
import 'role_repository.dart';

class RoleResolver {
  RoleResolver(this._repository);
  final RoleRepository _repository;
  Future<AppRole?> resolve() => _repository.loadRole();
}
