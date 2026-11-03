version=$(head -n 5 pubspec.yaml | tail -n 1 | cut -d ' ' -f 2)

flutter build linux --release -t lib/src/main.dart \
&& mkdir ~/Desktop/AcervoHC_${version} \
&& cp -r build/linux/x64/release/bundle/* ~/Desktop/AcervoHC_${version}/ \
&& cd ~/Desktop \
&& zip -ro AcervoHC_${version}.zip AcervoHC_${version} \
&& rm -rf mkdir ~/Desktop/AcervoHC_${version}
