Pod::Spec.new do |s|
  s.name             = 'onnxruntime-c'
  s.version          = '1.20.0'
  s.summary          = 'ONNX Runtime C library'
  s.homepage         = 'https://onnxruntime.ai'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = 'Microsoft'
  s.source           = { :path => '.' }
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.15'
  s.vendored_frameworks = 'onnxruntime.xcframework'
  s.module_name = 'onnxruntime'
  s.library = 'c++'
  
  # Expose headers with correct structure
  s.source_files = 'include/**/*.h'
  s.header_mappings_dir = 'include'
  
  s.pod_target_xcconfig = { 
    'OTHER_LDFLAGS' => '-lc++',
    'HEADER_SEARCH_PATHS' => '$(PODS_EXPORED_INCLUDE_PATHS) $(PODS_ROOT)/../Vendors/onnxruntime-c/include'
  }
end
