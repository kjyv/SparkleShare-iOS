## iOS app for [SparkleShare](http://www.sparkleshare.org)

Note: this requires a [SparkleShare Dashboard](https://github.com/kjyv/SparkleShare-dashboard/) to be set up for
your SparkleShare git projects.

### Features ###

 - Linking with Dashboard (both with QR code or manual)
 - Browsing repos contents
 - Previewing and editing (text) files
 - Render Markdown files

### Planned features ###

 - Uploading files
 - allowing self-signed certificates
 - displaying more file types

### Build on macOS

* Execute:

```sh
git clone git://github.com/kjyv/SparkleShare-iOS.git
cd SparkleShare-iOS
git submodule update --init
open SparkleShare.xcodeproj
```

Then build SparkleShare in Xcode

On iOS, you'll need to allow the development certificate in Settings -> General -> Profiles & Device Management
