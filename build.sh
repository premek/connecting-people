#!/usr/bin/env bash

set -x

P="connecting"
T="Connecting People"
PACKAGE="com.github.premek.${P//-/}"


LV="11.4" # TODO take from conf.lua
LZ="https://github.com/love2d/love/releases/download/${LV}/love-${LV}-win32.zip"
APK="https://github.com/love2d/love/releases/download/${LV}/love-${LV}-android.apk"
APKSIGNER="https://github.com/patrickfav/uber-apk-signer/releases/download/v0.8.4/uber-apk-signer-0.8.4.jar"
APKTOOL="https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.3.3.jar"

AndroidOrientation="portrait" # locked? # https://developer.android.com/guide/topics/manifest/activity-element#screen




### clean

if [ "$1" == "clean" ]; then
 rm -rf "target"
 exit;
fi



##### build #####

find . -iname "*.lua" | xargs luac -p || { echo 'luac parse test failed' ; exit 1; }

mkdir -p "target"



if [ "$1" == "dist" ]; then
 shift


### .love

cp -r src target
cd target/src

# compile .ink story into lua table so the runtime will not need lpeg dep.
#luarocks install --tree lua_modules lpeg
#LUA_PATH='lua_modules/share/lua/5.1/?.lua;lua_modules/share/lua/5.1/?/init.lua;;' LUA_CPATH='lua_modules/lib/lua/5.1/?.so' lua lib/pink/pink/pink.lua parse game.ink > game.lua

zip -9 -r - . > "../${P}.love"
cd -

### .exe

if [ ! -f "target/love-win.zip" ]; then wget "$LZ" -O "target/love-win.zip"; fi
#cp ~/downloads/love-0.10.1-win32.zip "target/love-win.zip"
unzip -o "target/love-win.zip" -d "target"

tmp="target/tmp/"
mkdir -p "$tmp/$P"
cat "target/love-${LV}-win32/love.exe" "target/${P}.love" > "$tmp/${P}/${P}.exe"
cp  target/love-"${LV}"-win32/*dll target/love-"${LV}"-win32/license* "$tmp/$P"
cd "$tmp"
zip -9 -r - "$P" > "${P}-win.zip"
cd -
cp "$tmp/${P}-win.zip" "target/"
rm -r "$tmp"


### android


#version from git - first char has to be number(no?)
#V="`git describe --tags`"
V="`git rev-parse --short HEAD`"
if [ $? -ne 0 ]; then  V=""; fi
#until [ -z "$V" ] || [ "${V:0:1}" -eq "${V:0:1}" ] 2>/dev/null; do V="${V:1}"; done
#if test -z "$V"; then V="0.0.1-snapshot"; fi;
#FIXME this breaks so often
# APKVersionCode=`echo "$V-0-0" | sed -e 's/\([0-9]\+\)[.-]\([0-9]\+\)[.-]\([0-9]\+\)[.-].*/\1 \2 \3/g' | xargs printf "%02d%03d%04d"`
APKVersionCode=`date +%s`
[[ 1"$APKVersionCode" -eq 1"$APKVersionCode" ]] || { echo "APKVersionCode Not a number"; exit 1; }



wget -c "$APKTOOL" -O "target/apktool.jar" &
wget -c "$APK" -O "target/love-android.apk" &
wget -c "$APKSIGNER" -O target/uber-apk-signer.jar &
wait

rm -r target/love_apk_decoded
java -jar target/apktool.jar d -s -o target/love_apk_decoded target/love-android.apk
#mkdir -p target/love_apk_decoded/assets
cp -r "src" target/love_apk_decoded/assets

convert -resize 48x48 resources/icon.png target/love_apk_decoded/res/drawable-mdpi/love.png
convert -resize 72x72 resources/icon.png target/love_apk_decoded/res/drawable-hdpi/love.png
convert -resize 96x96 resources/icon.png target/love_apk_decoded/res/drawable-xhdpi/love.png
convert -resize 144x144 resources/icon.png target/love_apk_decoded/res/drawable-xxhdpi/love.png
convert -resize 192x192 resources/icon.png target/love_apk_decoded/res/drawable-xxxhdpi/love.png

#cat <<EOF > target/love_apk_decoded/AndroidManifest.xml
#<?xml version="1.0" encoding="utf-8" standalone="no"?> <manifest package="${PACKAGE}" android:versionCode="${APKVersionCode}" android:versionName="${V}" android:installLocation="auto" xmlns:android="http://schemas.android.com/apk/res/android">
#    <uses-permission android:name="android.permission.INTERNET"/>
#    <uses-permission android:name="android.permission.VIBRATE"/>
#    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
#    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
#    <uses-feature android:glEsVersion="0x00020000"/>
#    <application android:allowBackup="true" android:icon="@drawable/love" android:label="${T}" android:theme="@android:style/Theme.NoTitleBar.Fullscreen" >
#        <activity android:configChanges="orientation|screenSize" android:label="${T}" android:launchMode="singleTop" android:name="org.love2d.android.GameActivity" android:screenOrientation="${AndroidOrientation}" > <intent-filter>
#                <action android:name="android.intent.action.MAIN"/>
#                <category android:name="android.intent.category.LAUNCHER"/>
#                <category android:name="tv.ouya.intent.category.GAME"/>
#            </intent-filter> </activity> </application> </manifest>
#EOF

#TODO versions
sed -ie "s/package=\"org.love2d.android\"/package=\"${PACKAGE}\"/" target/love_apk_decoded/AndroidManifest.xml 
sed -ie "s/LÖVE for Android/$T/" target/love_apk_decoded/AndroidManifest.xml 
sed -ie "s/android:screenOrientation=\"landscape\"/android:screenOrientation=\"${AndroidOrientation}\"/" target/love_apk_decoded/AndroidManifest.xml

#sed -ie "s/minSdkVersion.*/minSdkVersion: '16'/" target/love_apk_decoded/apktool.yml 
#sed -ie "s/targetSdkVersion.*/targetSdkVersion: '26'/" target/love_apk_decoded/apktool.yml 

java -jar target/apktool.jar b -o "target/$P.apk" target/love_apk_decoded
java -jar target/uber-apk-signer.jar --apks "target/$P.apk"
rm "target/$P.apk" # not installable, do not dist
#TODO prod sign



fi #dist




##### install android apk #####

if [ "$1" == "installapk" ]; then
	shift
	adb install -r "target/$P-aligned-debugSigned.apk"
	adb shell monkey -p "$PACKAGE" 1
fi #installapk




### web

if [ "$1" == "web" ]; then

cd target
rm -rf love.js *-web*
#npm i love.js
mem=$((`stat --printf="%s" "$P.love"` + 16000000)) # not sure about this, it just needs to be big enough
#npx love.js --compatibility --memory $mem --title "$P" "$P.love" "$P-web"
npx love.js --compatibility --title "$P" "$P.love" "$P-web"
echo "footer, h1 {display:none} body{background:#222}" > "$P-web/theme/love.css"

zip -9 -r - "$P-web" > "${P}-web.zip"
# target/$P-web/ goes to webserver

  if [ "$2" == "run" ]; then
    cd "$P-web"
    python3 -m http.server
  fi
fi
