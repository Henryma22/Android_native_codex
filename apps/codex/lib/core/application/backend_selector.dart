import '../../backends/local/local_android_backend.dart';
import '../../backends/compatibility/linux_compatibility_backend.dart';
import '../../backends/fake/fake_backend.dart';
import '../../services/linux_compatibility_runtime.dart';
import '../domain/backend.dart';

class BackendSelector {
  BackendSelector(Iterable<Backend> backends)
    : _backends = List<Backend>.unmodifiable(backends);

  factory BackendSelector.development() =>
      BackendSelector(<Backend>[FakeBackend()]);

  factory BackendSelector.device() {
    final local = LocalAndroidBackend();
    return BackendSelector(<Backend>[
      local,
      LinuxCompatibilityBackend(
        local,
        runtime: AndroidCompatibilityRuntimeClient(),
      ),
    ]);
  }

  List<Backend> _backends;

  List<Backend> get backends => _backends;

  List<BackendDescriptor> get descriptors =>
      _backends.map((backend) => backend.descriptor).toList(growable: false);

  Backend select(String backendId) {
    for (final backend in _backends) {
      if (backend.descriptor.id == backendId) {
        return backend;
      }
    }
    throw BackendException('Backend not found: $backendId');
  }
}
