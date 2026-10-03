# Aggiunge al progetto Xcode l'app per Apple Watch (RecompWatch) e la complicazione sul quadrante (RecompWatchWidgets),
# incorporate nell'app iPhone. Solo per le compilazioni da Xcode sul Mac (WATCH=1 in prepara.sh): la versione per
# AltStore resta senza, perché AltStore non installa bene le app Watch.
# I file vengono copiati da prepara.sh in ios/App/RecompWatch e ios/App/RecompWatchWidgets prima di lanciare questo script.
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/App/App.xcodeproj')
app = project.targets.find { |t| t.name == 'App' } or abort('target App non trovato')
# l'app Watch deve avere la stessa versione dell'app iPhone che la contiene
base = app.build_configurations.first.build_settings
version = base['MARKETING_VERSION'] || '1.0'
build = base['CURRENT_PROJECT_VERSION'] || '1'

def watch_settings(target, bundle, folder, version, build)
  target.build_configurations.each do |c|
    s = c.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = bundle
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['INFOPLIST_FILE'] = "#{folder}/Info.plist"
    s['GENERATE_INFOPLIST_FILE'] = 'NO'
    s['CODE_SIGN_ENTITLEMENTS'] = "#{folder}/#{folder}.entitlements"
    s['MARKETING_VERSION'] = version
    s['CURRENT_PROJECT_VERSION'] = build
    s['SWIFT_VERSION'] = '5.0'
    s['TARGETED_DEVICE_FAMILY'] = '4'
    s['WATCHOS_DEPLOYMENT_TARGET'] = '10.0'
    s['SKIP_INSTALL'] = 'YES'
    yield s if block_given?
  end
end

# 1. app Watch (una sola destinazione, come le app Watch di Xcode 14 e successivi)
watch = project.new_target(:application, 'RecompWatch', :watchos, '10.0', nil, :swift)
wgroup = project.main_group.new_group('RecompWatch', 'RecompWatch')
watch.add_file_references(%w[RecompWatchApp.swift WatchStore.swift WatchModel.swift].map { |f| wgroup.new_reference(f) })
watch.add_resources([wgroup.new_reference('Assets.xcassets')])
%w[Info.plist RecompWatch.entitlements].each { |f| wgroup.new_reference(f) }
watch_settings(watch, 'io.github.splancxs.recomp.watchkitapp', 'RecompWatch', version, build) do |s|
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
end

# 2. complicazione (estensione WidgetKit dentro l'app Watch)
widgets = project.new_target(:app_extension, 'RecompWatchWidgets', :watchos, '10.0', nil, :swift)
xgroup = project.main_group.new_group('RecompWatchWidgets', 'RecompWatchWidgets')
widgets.add_file_references(%w[RecompWatchWidgets.swift WatchModel.swift].map { |f| xgroup.new_reference(f) })
%w[Info.plist RecompWatchWidgets.entitlements].each { |f| xgroup.new_reference(f) }
%w[WidgetKit SwiftUI].each { |fw| widgets.add_system_framework(fw) }
watch_settings(widgets, 'io.github.splancxs.recomp.watchkitapp.widgets', 'RecompWatchWidgets', version, build) do |s|
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end
watch.add_dependency(widgets)
embed_ext = watch.new_copy_files_build_phase('Embed Foundation Extensions')
embed_ext.symbol_dst_subfolder_spec = :plug_ins
embed_ext.add_file_reference(widgets.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# 3. l'app iPhone contiene l'app Watch nella cartella Watch
app.add_dependency(watch)
embed_watch = app.new_copy_files_build_phase('Embed Watch Content')
embed_watch.symbol_dst_subfolder_spec = :products_directory
embed_watch.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
embed_watch.add_file_reference(watch.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts 'App Watch e complicazione aggiunte al progetto.'
