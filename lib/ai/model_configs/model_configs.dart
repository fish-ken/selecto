// Barrel + registry for the bundled model configs. Import this file to
// get the ModelConfig base, every concrete config, and the kModelConfigs
// list in one go.
export 'maniqa10k_config.dart';
export 'model_config.dart';
export 'nima_mobile_net_aesthetic_config.dart';
export 'nima_mobile_net_technical_config.dart';

import 'maniqa10k_config.dart';
import 'model_config.dart';
import 'nima_mobile_net_aesthetic_config.dart';
import 'nima_mobile_net_technical_config.dart';

/// The model registry. Order = dropdown order; the first entry is the
/// default selection. Select one by index/identity and drive preprocessing
/// + extraction from it. Add a new model by creating its config file in
/// this directory and appending an instance here.
///
/// NIMA Technical is first so it's the default model on launch.
const List<ModelConfig> kModelConfigs = [
  NimaMobileNetTechnicalConfig(),
  NimaMobileNetAestheticConfig(),
  Maniqa10kConfig(),
];
