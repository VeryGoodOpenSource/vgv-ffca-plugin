import 'package:tau_domain/tau_domain.dart';

// Exports its DTOs and mappers along with the repository and data source.
export 'data_sources/tau_remote_data_source/dtos/tau_dto.dart';
export 'mappers/tau_mapper.dart';
export 'repositories/tau_repository.dart';
// The app constructs the data source, so exporting it is allowed.
export 'data_sources/tau_remote_data_source/tau_remote_data_source.dart';
