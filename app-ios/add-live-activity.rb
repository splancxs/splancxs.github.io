# Aggiunge al progetto Xcode generato da "npx cap add ios" (gira su macOS, dentro GitHub Actions):
#  - nell'app: il plugin RestActivity e i dati della Live Activity;
#  - l'estensione RecompLive (WidgetKit) che disegna la Live Activity del recupero, incorporata nell'app.
# I file Swift vengono copiati dal workflow in ios/App/App e ios/App/RecompLive prima di lanciare questo script.
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/App/App.xcodeproj')
app = project.targets.find { |t| t.name == 'App' } or abort('target App non trovato')

# 1. file nativi dell'app (gruppo "App" = cartella ios/App/App)
app_group = project.main_group.find_subpath('App', false) or abort('gruppo App non trovato')
%w[RestAttributes.swift RestActivityPlugin.swift].each do |f|
  app.add_file_references([app_group.new_reference(f)])
end
# ActivityKit esiste da iOS 16.1: l'app parte da 16.2 come l'estensione (l'iPhone 14 ha almeno iOS 16)
app.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.2' }

# 2. estensione RecompLive
ext = project.new_target(:app_extension, 'RecompLive', :ios, '16.2', nil, :swift)
ext_group = project.main_group.new_group('RecompLive', 'RecompLive')
ext.add_file_references(%w[RestAttributes.swift RestLiveActivity.swift].map { |f| ext_group.new_reference(f) })
ext_group.new_reference('Info.plist')
%w[WidgetKit SwiftUI].each { |fw| ext.add_system_framework(fw) }
ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.github.splancxs.recomp.live'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'RecompLive/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['MARKETING_VERSION'] = '1.0'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '16.2'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

# 3. l'app dipende dall'estensione e la copia nella cartella PlugIns
app.add_dependency(ext)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
build_file = embed.add_file_reference(ext.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts 'Estensione RecompLive aggiunta al progetto.'
