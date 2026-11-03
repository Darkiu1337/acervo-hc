version=$(head -n 5 pubspec.yaml | tail -n 1 | cut -d ' ' -f 2)

flutter build windows -t lib/src/main.dart \
&& cp -r build/windows/runner/Release/ ~/Desktop/AcervoHC_${version}_windows/ \
&& cd ~/Desktop \
&& zip -ro AcervoHC_${version}_windows.zip AcervoHC_${version}_windows \
&& rm -rf AcervoHC_${version}_windows
