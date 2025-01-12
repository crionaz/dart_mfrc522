//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <mfrc522/mfrc522_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) mfrc522_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "Mfrc522Plugin");
  mfrc522_plugin_register_with_registrar(mfrc522_registrar);
}
