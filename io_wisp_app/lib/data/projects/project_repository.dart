import '../../domain/project.dart';

abstract class ProjectRepository {
  List<Project> getAll();

  Project? findById(String id);

  Project? findByNormalizedName(String normalizedName);

  void insert(Project project);

  void update(Project project);
}
