# Phosphor icons in SOOM

SOOM uses the official [Phosphor core](https://github.com/phosphor-icons/core) SVG paths, pinned to commit `2b75f3ad12b420c9504ef05df8d2564a28f8500e`. `manifest.json` records the icon mapping and SHA-256 of every vendored source. `LICENSE` is the unchanged upstream MIT notice. The same notice is shipped in the `PhosphorLicense` data asset, so it is included in the distributed app without another package or bundle-resource build phase.

## Selection

[React Native Vector Icons](https://github.com/oblador/react-native-vector-icons) exposes React Native components/font packages. Its own MIT license is separate from each included icon font's license. SOOM is a native SwiftUI/UIKit app and does not require a React Native runtime.

Phosphor has a consistent family and an [official SwiftUI port](https://github.com/phosphor-icons/swift). That port's images are resizable by default. SOOM already sizes icons through SwiftUI `.font` and UIKit `UIImage.SymbolConfiguration`, so a plain image replacement would change existing sizing. SOOM packages the official paths as [Apple custom symbol assets](https://developer.apple.com/documentation/uikit/creating-custom-symbol-images-for-your-app) to retain these native behaviors. No upstream Swift package code is incorporated.

## Native API

```swift
Image(soom: SOOMIcon.bookmark)
    .font(.system(size: 20, weight: .regular))
Image(soom: SOOMIcon.home, selected: isSelected)
Label("저장", soomIcon: SOOMIcon.bookmark)
Button("삭제", soomIcon: SOOMIcon.trash, role: .destructive) { delete() }
ContentUnavailableView("기록 없음", soomIcon: SOOMIcon.activity)
UIImage(soom: SOOMIcon.medal, withConfiguration: .init(pointSize: 18))
```

`Image(soom:)` returns `SwiftUI.Image`, not a wrapper view. This preserves Image-specific modifiers and type constraints. Labels keep native text, accessibility, baseline layout and label styles. Existing stable String icon keys are translated at rendering time; persisted model values remain valid. `apple.logo` stays Apple's brand symbol. Unknown remote/model keys render the Phosphor question icon, while the source audit rejects unknown explicit UI keys.

Default variants use Phosphor regular; semibold/bold font weights use the original bold paths. Selected variants use fill. All symbols contain small/medium/large variants and explicit baseline/cap-height/margin guides. Navigation chevrons and standard controls retain the original frame and accessibility labels. The callers own a minimum 44 pt touch target; an icon's visual size does not define its hit area. Content images and service logos are outside the migration.

## Reproduce and integrate

1. `python3 scripts/dev/sync_phosphor_icons.py --check` verifies original hashes and all generated artifacts without network access.
2. If an intentional mapping change is needed, edit `manifest.json`, vendor the exact new original SVGs with hashes, then run `python3 scripts/dev/sync_phosphor_icons.py --write`. Never edit generated symbol paths or the generated Swift map.
3. After parallel screen work ends, run `python3 scripts/dev/migrate_soom_icons.py` to review the call-site plan; then `--apply` to migrate only known icon initializer argument labels.
4. Run `python3 scripts/dev/migrate_soom_icons.py --check` and `python3 -m unittest discover -s scripts/dev -p 'test_migrate_soom_icons.py'`.
5. Register `SOOM/DesignSystem/SoomPhosphor.swift` and `SOOMTests/SOOMIconTests.swift` in the respective Xcode targets. Existing Assets.xcassets compiles the symbols and license automatically.
6. Run the app test target and visually inspect Feed, Activity, Profile, Settings, Record, the shared detail, menus, and map badges at default and accessibility text sizes. Selected tabs should pass `selected: isSelected` explicitly.

The generator does not modify the Xcode project or application screens. The migration scanner preserves comments, strings, model values, nested helper parameters, photos and action bodies; it is idempotent. No automatic upstream update or network asset fetch occurs in the app.
