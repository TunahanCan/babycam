import '../../app/app_role.dart';
import '../../app/role_repository.dart';

class RoleSelectionController {
  RoleSelectionController(this._repository);
  final RoleRepository _repository;
  Future<void> select(AppRole role) => _repository.saveRole(role);
}
