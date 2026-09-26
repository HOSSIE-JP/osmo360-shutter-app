# Osmo 360 Shutter

歩いて、止まって、360°を残す。

Flutter製のAndroid / PWAアプリ。Material 3のダークUIで、DJI Osmo 360をBLE経由で操作し、歩行→静止でパノラマ静止画を撮影します。**前面利用専用・実機評価版**です。

- [PWAを開く](https://hossie-jp.github.io/osmo360-shutter-app/)
- [開発ブランチ](https://github.com/HOSSIE-JP/osmo360-shutter-app/tree/osmo360-shutter-app)
- [Android APKのビルド](https://github.com/HOSSIE-JP/osmo360-shutter-app/actions/workflows/android.yml) — 成功した実行のArtifactsから取得

## 機能

- 接続承認コード、パノラマ写真モード切替・確認、手動シャッター、カメラ状態・バッテリー・容量。
- 歩数×歩幅で撮影間隔を案内。ジャイロと加速度の連続静止で1回だけ撮影要求。
- 手動・自動共通のクールダウン、カメラの処理待ち、音・日本語音声・振動通知。
- 有効なGPS位置を継続送信。古い測位・欠測・許容精度超過を保留。
- プロジェクトの新規作成・編集・削除。プロジェクトごとに複数の撮影セッションを保存。
- 各撮影要求の時刻、座標、水平／垂直精度、楕円体高、カメラ応答、撮影動作の検知を確認。
- APIキーなし：GPS相対座標の2D軌跡、ドラッグ回転・ピンチ拡大縮小できる3D軌跡、高度グラフ。
- APIキーあり：Google Maps JavaScript APIによる地図、移動線、番号付き撮影地点。
- JSON（詳細ログ）・CSV（撮影一覧）・GPX（軌跡）・プロジェクト全体JSONの書き出し。
- カメラなしで操作できるデモモード。

## 使い方

1. Android ChromeでPWAを開き、ブラウザーの「アプリをインストール」または右上のインストールボタンを使います。
2. 「プロジェクト」で撮影場所・目的ごとのプロジェクトを作成します。
3. カメラの電源とBluetoothをONにし、他のコントローラーとの接続を解除します。
4. 「カメラを接続」から選択し、カメラ画面で表示コードを承認します。
5. 「写真モード」でパノラマ写真モードを確認。解像度、露出、画像形式はカメラ側で設定します。
6. スマホをカメラと同じポールへ固定し、セッションを開始。位置情報と動作センサーを許可します。
7. 設定距離を歩き、音声ガイド後に静止します。初期値は3m間隔、1.5秒静止、6秒クールダウンです。
8. セッション終了後、「プロジェクト」内の詳細から履歴・軌跡を確認します。

画面が非表示になった場合や切断時には一時停止します。前面に戻して接続・GPSを確認し、**明示的に再開**してください。通信結果が不明なシャッターは自動再送しません。長時間利用前に、下記の実機チェックを実施してください。

## 地図APIキー

「設定 → 地図APIキー」でGoogle Maps JavaScript API用のキーを入力します。Google Cloud側でMaps JavaScript APIと課金を有効にする必要があります。HTTPリファラー制限は `https://hossie-jp.github.io/*` を使用してください。キーのAPI制限はMaps JavaScript APIに限定します。

キーはこの端末内だけに保存し、プロジェクトのJSON・CSV・ログには含めません。地図を表示すると、キーと表示位置をGoogleに送信します。地図表示をOFFにするかキーを空欄にするとGoogle Mapsは読み込みません。通信不可・無効なキーの場合でも相対座標ビューは使えます。

Androidも同じ地図HTMLをアプリ内WebViewで表示します。HTTPリファラー制限が利用端末のWebViewで通るかは実機検証項目です。Googleの3D地形ではなく、**相対座標3Dビューが高度を含む撮影軌跡を表示**します。

## 対応と制限

| 項目 | Android | PWA |
|---|---|---|
| BLE | ネイティブGATT | Web Bluetooth対応Chrome |
| 歩数 | STEP_DETECTORが利用可能なら使用、他は加速度推定 | 加速度推定 |
| 停止判定 | ジャイロ＋線形加速度 | DeviceMotionの回転速度＋線形加速度 |
| 地図／3D | 対応 | 対応 |
| 保存 | アプリ内AtomicFile | IndexedDB |
| 前面維持 | KEEP_SCREEN_ON | Screen Wake Lock（対応時） |
| 非表示・消灯後 | 撮影停止・手動再開 | 撮影停止・手動再開 |

- 推定歩数・距離とGPS座標には誤差があります。ポケット運用はカメラ自体の静止を保証しません。
- 「要求受理」「撮影動作を検知」は、画像ファイルの保存成功を保証しません。BLE仕様には画像転送・ファイル名付き保存完了通知がありません。
- GPS高度は楕円体高で、海抜高度ではありません。GPXには誤った海抜高度を書かないよう `ele` を出力せず、JSON/CSVに基準付き高度を保持します。
- 高度が欠測している場合はカメラへのGPS送信を保留します。ブラウザーで取得できない衛星数は0、未取得の精度は最大誤差値とし、良好なGNSS品質を捏造しません。この値をカメラがどう扱うかは実機確認が必要です。
- GPSは1Hz送信。再送でも元の測位時刻を保持します。公式例のUTC+8を日付繰り上がり込みで変換し、UTC送信にも設定で切り替え可能です。
- Chromeのストレージ消去・アプリ削除・プライベートモード終了で記録が消える場合があります。大事な撮影後は書き出してください。
- 各セッションの診断ログは最新1500件、軌跡は最新12000地点を保持。撮影要求の一覧と保存済みセッションは自動削除しません。
- 保存成功、GPSのEXIF埋め込み、120MP等の写真設定別動作、端末ごとのセンサー感度は**実機未検証**です。

## 開発

Flutter **3.35.5**、Dart 3.9系をCIで固定しています。外部Flutterプラグインを使わず、共有Dartコア＋Web API / Kotlinの端末アダプターで構成しています。

```sh
flutter pub get
python3 tool/make_icons.py
flutter analyze
flutter test
node --test test/web_bridge_test.cjs
flutter run -d chrome
```

Android（Windowsでは `python3` を `python` に置き換え）：

```sh
python3 tool/bootstrap_android.py
flutter run -d <android-device-id>
flutter build apk --debug
```

標準のFlutter Androidラッパーは初回に生成し、`android_src/` のKotlinコードとManifestを適用します。必要なAndroid SDKはFlutterの通常のセットアップで導入してください。配布署名鍵は含めません。CIのAPKは実機評価用debug APKです。

PWAビルド：

```sh
flutter build web --release --base-href /osmo360-shutter-app/ --pwa-strategy=none --no-web-resources-cdn
python3 tool/build_pwa.py
```

`osmo360-shutter-app` ブランチへのpushで検証し、成功したFlutter WebビルドをPagesへ公開します。独自Service Workerは同じリリースのアセットをまとめてキャッシュし、撮影中に新バージョンへ強制切替しません。更新時は全タブ・PWAを一度閉じて開き直します。

## 資料

- [構成・判定ルール](docs/ARCHITECTURE.md)
- [実機検証チェックリスト](docs/HARDWARE_TESTS.md)
- [検証結果](docs/VALIDATION.md)
- [参照仕様・利用条件](THIRD_PARTY_NOTICES.md)

本アプリはDJIの公式製品ではありません。
