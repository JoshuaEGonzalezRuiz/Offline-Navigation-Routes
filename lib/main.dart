import 'package:flutter/material.dart';
import 'package:here_sdk/consent.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/core.engine.dart';
import 'package:here_sdk/core.errors.dart';
import 'package:offline_navigation_routes/values/strings.dart';

import 'pages/map_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SdkContext.init(IsolateOrigin.main);

  // Set your credentials for the HERE SDK.
  String accessKeyId = "YOUR_ACCESS_KEY_ID";

  String accessKeySecret =
      "YOUR_ACCESS_KEY_SECRET";

  SDKOptions sdkOptions =
  SDKOptions.withAccessKeySecret(accessKeyId, accessKeySecret);

  sdkOptions.catalogConfigurations = [
    CatalogConfiguration(DesiredCatalog(
        "hrn:here:data::olp-here:ocm", CatalogVersionHint.latest())),
    /*CatalogConfiguration(DesiredCatalog(
        "hrn:here:data::olp-here:ocm-japan", CatalogVersionHint.latest()))*/
  ];

  try {
    await SDKNativeEngine.makeSharedInstance(sdkOptions);

    runApp(const MyOfflineNavRouting());
  } on InstantiationException {
    throw Exception("Failed to initialize the HERE SDK.");
  }
}

class MyOfflineNavRouting extends StatelessWidget {
  const MyOfflineNavRouting({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      // Add consent localization delegates.
      debugShowCheckedModeBanner: false,
      localizationsDelegates: HereSdkConsentLocalizations.localizationsDelegates,
      // Add supported locales.
      supportedLocales: HereSdkConsentLocalizations.supportedLocales,
      title: title_app,
      home: MyMapViewPage(title: title_app),
    );
  }
}