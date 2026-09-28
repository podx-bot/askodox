# Companion engine page (assets/companion/engine.html)

three.js 0.169.0 + @pixiv/three-vrm 3.5.5 (both MIT), bundled with esbuild:

    npm i three@0.169.0 @pixiv/three-vrm@3.5.5 esbuild@0.24.0
    npx esbuild engine.js --bundle --minify --format=iife --target=es2019 --outfile=engine.min.js

then inline engine.min.js into assets/companion/engine.html (see the git
history of that file). Bundle: ~695 KB raw, ~175 KB gzip.
