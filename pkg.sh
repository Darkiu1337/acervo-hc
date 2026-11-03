version=$(head -n 5 pubspec.yaml | tail -n 1 | cut -d ' ' -f 2)

flutter build macos --release -t lib/src/main.dart \
&& hdiutil create -size 150m -fs HFS+ -volname AcervoHC AcervoHC.dmg \
&& hdiutil attach AcervoHC.dmg \
&& cp -R build/macos/Build/Products/Release/Acervo HC.app /Volumes/AcervoHC \
&& pkgbuild --install-location "/Applications/Acervo HC.app" --identifier app.acervo.hc --version ${version} --root /Volumes/AcervoHC/Acervo HC.app build/macos/AcervoHC-${version}.pkg \
&& hdiutil detach /Volumes/AcervoHC
