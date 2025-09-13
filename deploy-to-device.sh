#!/bin/bash

# xcodebuild -scheme SparkleShare -destination 'platform=iOS,name=Stefan’s iPhone' build
#
xcodebuild archive \
-scheme SparkleShare \
-configuration Release \
-archivePath `pwd`/SparkleShare.xcarchive \
-destination 'platform=iOS,name=Stefan’s iPhone' \
-project SparkleShare.xcodeproj \
-allowProvisioningUpdates

xcodebuild -exportArchive \
-archivePath `pwd`/SparkleShare.xcarchive \
#-exportOptionsPlist `pwd`/ExportOptions.plist \
-exportPath `pwd`/export/SparkleShare.ipa \
-allowProvisioningUpdates

ios-deploy --bundle `pwd`/SparkleShare.xcarchive/Products/Applications/SparkleShare.app --id 00008110-001249961E46801E
