import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/core.engine.dart';
import 'package:here_sdk/core.errors.dart';
import 'package:here_sdk/gestures.dart';
import 'package:here_sdk/maploader.dart';
import 'package:here_sdk/mapview.dart';
import 'package:here_sdk/routing.dart';
import 'package:offline_navigation_routes/values/colors.dart';
import 'package:offline_navigation_routes/values/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:here_sdk/routing.dart' as here;
import 'package:here_sdk/navigation.dart' as navigation;

class MyMapViewPage extends StatefulWidget {
  const MyMapViewPage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyMapViewPage> createState() => _MyMapViewPageState();
}

class _MyMapViewPageState extends State<MyMapViewPage> {
  HereMapController? _hereMapController;
  SDKNativeEngine? sdkNativeEngine = SDKNativeEngine.sharedInstance;
  late MapDownloader _mapDownloader;
  late MapUpdater _mapUpdater;
  OfflineRoutingEngine? _offlineRoutingEngine;
  List<Region> _downloadableRegions = [];
  final List<MapDownloaderTask> _mapDownloaderTasks = [];
  final List<CatalogUpdateTask> _mapUpdateTasks = [];
  final double _distanceToEarthInMeters = 250000;
  GeoCoordinates? _defaultCoordinates;

  late SharedPreferences devicePrefs;
  bool hasOfflineData = false;
  bool hasRegions = false;
  bool isDownloading = false;
  bool expanded = false;
  late List<Region> childRegions;
  String downloadText = "";
  String countryName = "";
  String placeName = "";

  MapImage? _poiMapImage;
  final List<MapMarker> _mapMarkerList = [];
  late here.Route route;
  final List<MapPolyline> _mapPolylines = [];

  bool putFirstMarker = true;
  bool showRouteInfo = false;
  bool enableResetCameraPosition = true;
  bool enableReset = false;
  bool enableNavigation = false;
  bool stopNavigation = false;
  bool showInfoNavigation = false;
  int flagMarkers = 0;

  String travelTime = '';
  String travelLength = '';
  String navigationInfo = '';

  late navigation.VisualNavigator _visualNavigator;
  late navigation.LocationSimulator _locationSimulator;

  var newOrientation = GeoOrientationUpdate(0.0, 0.0);

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    if (sdkNativeEngine == null) {
      throw ("SDKNativeEngine not initialized.");
    }


    MapDownloader.fromSdkEngineAsync(sdkNativeEngine!, (mapDownloader) {
      _mapDownloader = mapDownloader;

      MapUpdater.fromSdkEngineAsync(sdkNativeEngine!, (mapUpdater) {
        _mapUpdater = mapUpdater;
      });

      checkKeys();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background_color,
      appBar: AppBar(
        title: Text(
          hasOfflineData
              ? widget.title
              : hasRegions
                  ? title_download
                  : "",
          style: const TextStyle(color: general_color),
        ),
        backgroundColor: general_background_color,
        actions: [
          hasOfflineData ? IconButton(onPressed: (){
            _showDialogs("Remove offline map data", info_erase_message, "b");
          }, icon: Icon(Icons.youtube_searched_for, color: subgeneral_color,)) :
          IconButton(onPressed: (){
            _showDialogs("What's this?", info_connection_message, "i");
          }, icon: Icon(Icons.info, color: subgeneral_color,))
        ],
      ),
      body: Center(
        child: isDownloading ? Container(
            padding: EdgeInsets.all(16),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                      child: SizedBox(
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            backgroundColor: Colors.transparent,
                            color: general_color,
                          ),
                          width: 32,
                          height: 32),
                      padding: EdgeInsets.only(bottom: 16)),
                  const Padding(
                      child: Text(
                        'Please wait …',
                        style: TextStyle(
                            color: Colors.white, fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                      padding: EdgeInsets.only(top: 10, bottom: 10)),
                  Text(
                    downloadText,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  )
                ])) : hasOfflineData
            ? Stack(
          children: [
            HereMap(onMapCreated: _onMapCreated),
            Align(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Tooltip(
                    message: 'Reset position of the map',
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          primary: general_background_color,
                          shape: const CircleBorder()),
                      child: const Icon(Icons.gps_fixed,
                          color: general_color),
                      onPressed: _hereMapController != null &&
                          enableResetCameraPosition
                          ? () {
                        _hereMapController?.camera
                            .lookAtPointWithGeoOrientationAndDistance(
                            _defaultCoordinates!,
                            newOrientation,
                            _distanceToEarthInMeters);
                      }
                          : null,
                    ),
                  ),
                  Tooltip(
                    message: "Clear the map",
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          primary: general_background_color,
                          shape: const CircleBorder()),
                      child: const Icon(Icons.restart_alt,
                          color: Colors.red),
                      onPressed: enableReset
                          ? () {
                        _clearMap();
                      }
                          : null,
                    ),
                  ),
                  stopNavigation
                      ? Tooltip(
                    message: "Stops navigating the current route",
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          primary: general_background_color,
                          shape: const CircleBorder()),
                      child: const Icon(Icons.stop,
                          color: general_color),
                      onPressed: enableNavigation
                          ? () {
                        _stopGuidance();
                      }
                          : null,
                    ),
                  )
                      : Tooltip(
                    message:
                    "Start navigation on the current route",
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          primary: general_background_color,
                          shape: const CircleBorder()),
                      child: const Icon(Icons.navigation,
                          color: general_color),
                      onPressed: enableNavigation
                          ? () {
                        _startGuidance(route);
                      }
                          : null,
                    ),
                  ),
                ],
              ),
              alignment: Alignment.bottomRight,
            ),
            showRouteInfo
                ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Card(
                        margin: EdgeInsets.fromLTRB(
                            MediaQuery.of(context).size.width * 0.07,
                            15,
                            MediaQuery.of(context).size.width * 0.07,
                            0),
                        elevation: 20,
                        color: general_background_color,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: ListTile(
                          minVerticalPadding:
                          MediaQuery.of(context).size.width * 0.02,
                          //trailing: Icon(Icons.straighten),
                          title: const Text(
                            title_route_length,
                            style: TextStyle(
                              color: general_color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          subtitle: Text(travelLength,
                              style: const TextStyle(
                                color: description_color,
                              ),
                              textAlign: TextAlign.center),
                        ),
                      ),
                    )),
                Flexible(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Card(
                          margin: EdgeInsets.fromLTRB(
                              MediaQuery.of(context).size.width * 0.07,
                              15,
                              MediaQuery.of(context).size.width * 0.07,
                              0),
                          elevation: 20,
                          color: general_background_color,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ListTile(
                            minVerticalPadding:
                            MediaQuery.of(context).size.width *
                                0.02,
                            //trailing: Icon(Icons.watch_later),
                            title: const Text(title_route_time,
                                style: TextStyle(
                                  color: general_color,
                                ),
                                textAlign: TextAlign.center),
                            subtitle: Text(travelTime,
                                style: const TextStyle(
                                  color: description_color,
                                ),
                                textAlign: TextAlign.center),
                          )),
                    )),
              ],
            )
                : const Center(
              child: Text(''),
            ),
            showInfoNavigation
                ? Align(
                alignment: Alignment.topRight,
                child: Card(
                  margin: const EdgeInsets.fromLTRB(5, 10, 5, 20),
                  elevation: 25,
                  color: general_background_color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(0, 5, 0, 5),
                    width: MediaQuery.of(context).size.width * 0.45,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: ListTile(
                      minLeadingWidth: 5,
                      title: Text(navigationInfo,
                          style: const TextStyle(
                            color: description_color,
                          )),
                      leading:
                      Icon(Icons.info, color: subgeneral_color),
                    ),
                  ),
                ))
                : const Center(
              child: Text(''),
            ),
          ],
        )
            : hasRegions
            ? Padding(
          padding: const EdgeInsets.all(10.00),
          child: ListView.builder(
              itemCount: childRegions.length,
              itemBuilder: (context, index) {
                return Card(
                  color: general_background_color,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(
                        color: regionsTextTileColor, width: 1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ExpansionTile(
                    textColor: regionsTileColor,
                    iconColor: regionsTileColor,
                    collapsedTextColor: regionsTextTileColor,
                    collapsedIconColor: regionsTextTileColor,
                    leading: const Icon(Icons.travel_explore),
                    title: Text(childRegions[index].name),
                    subtitle: Text(
                        'Regions: ${childRegions[index].childRegions!.length}'),
                    children: <Widget>[
                      Column(
                          children: buildChildRegion(
                              childRegions[index].childRegions))
                    ],
                  ),
                );
              }),
        )
            : const Center(
          child: CircularProgressIndicator(
            color: general_color,
          ),
        ),
      ),
    );
  }

  buildChildRegion(List<Region>? regions) {
    List<Widget> columnContent = [];

    for (Region content in regions!) {
      columnContent.add(content.childRegions != null
          ? Card(
              margin: const EdgeInsets.all(10.0),
              color: general_background_color,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: subRegionsColor, width: 1),
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              child: ExpansionTile(
                textColor: subTextRegionsColor,
                iconColor: subTextRegionsColor,
                collapsedTextColor: subRegionsColor,
                collapsedIconColor: subRegionsColor,
                leading: const Icon(Icons.flag),
                title: Text(content.name),
                onExpansionChanged: (ev) {
                  setState(() {
                    countryName = content.name;
                  });
                },
                subtitle: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sub regions: ${content.childRegions!.length}'),
                    IconButton(
                        onPressed: () {
                          print('Name: ' +
                              content.name +
                              ' Region id: ' +
                              content.regionId.id.toString());
                          onDownloadMapClicked(content.name, content.regionId);
                        },
                        color: buttonDownloadColor,
                        icon: const Icon(Icons.cloud_download))
                  ],
                ),
                children: <Widget>[
                  Column(children: buildSubChildRegion(content.childRegions))
                ],
              ),
            )
          : Card(
              margin: const EdgeInsets.all(10.0),
              color: general_background_color,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: subRegionsColor, width: 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.flag,
                  color: subRegionsColor,
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        content.name,
                        style: const TextStyle(color: subRegionsColor),
                      ),
                    ),
                    IconButton(
                        onPressed: () {
                          countryName.isNotEmpty
                              ? setState(() => countryName = "")
                              : "";
                          onDownloadMapClicked(content.name, content.regionId);
                        },
                        color: buttonDownloadColor,
                        icon: const Icon(Icons.cloud_download))
                  ],
                ),
              ),
            ));
    }
    return columnContent;
  }

  buildSubChildRegion(List<Region>? subRegions) {
    List<Widget> columnContent = [];
    for (Region content in subRegions!) {
      columnContent.add(Card(
        margin: const EdgeInsets.all(10.0),
        color: general_background_color,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: subSubRegionColor.withOpacity(0.6), width: 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          leading: const Icon(
            Icons.location_city,
            color: subSubRegionColor,
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                content.name,
                style: const TextStyle(color: subSubRegionColor),
              ),
              IconButton(
                  onPressed: () {
                    onDownloadMapClicked(content.name, content.regionId);
                    //print(content.regionId.id);
                  },
                  color: buttonDownloadColor,
                  icon: const Icon(Icons.cloud_download))
            ],
          ),
        ),
      ));
    }
    return columnContent;
  }

  void _onMapCreated(HereMapController hereMapController) {
    _hereMapController = hereMapController;
    hereMapController.mapScene.loadSceneForMapScheme(MapScheme.normalDay,
        (MapError? error) {
      if (error != null) {
        print('Map scene not loaded. MapError: ${error.toString()}');
        return;
      }

      _checkInstallationStatus();
    });
  }

  setMapFlagDataValue(String key, bool value) async {
    devicePrefs = await SharedPreferences.getInstance();
    devicePrefs.setBool(key, value);
  }

  setPlaceNameValue(String key, String value) async {
    devicePrefs = await SharedPreferences.getInstance();
    devicePrefs.setString(key, value);
  }

  Future<bool> getMapFlagDataValue(String key) async {
    devicePrefs = await SharedPreferences.getInstance();
    return devicePrefs.getBool(key) ?? false;
  }

  Future<String> getPlaceNameValue(String key) async {
    devicePrefs = await SharedPreferences.getInstance();
    return devicePrefs.getString(key) ?? "";
  }

  Future<bool> containsKey(String key) async {
    devicePrefs = await SharedPreferences.getInstance();
    return devicePrefs.containsKey(key);
  }

  Future<void> checkKeys() async {
    bool hasKey = await containsKey('hasOfflineMapData');
    bool hasPlaceName = await containsKey('placeName');
    bool hasRegionCoords = await containsKey('hasRegionCoords');

    if (hasKey && hasPlaceName && hasRegionCoords) {
      bool checkOfflineData = await getMapFlagDataValue('hasOfflineMapData');
      String checkPlaceName = await getPlaceNameValue('placeName');
      String checkRegionCoords = await getPlaceNameValue('hasRegionCoords');

      if (checkOfflineData &&
          checkPlaceName.isNotEmpty &&
          checkRegionCoords.isNotEmpty) {
        setState(() {
          hasOfflineData = checkOfflineData;
          placeName = checkPlaceName;
          var coords = checkRegionCoords.split(",");
          double? lat = double?.tryParse(coords[0]);
          double? lng = double?.tryParse(coords[1]);
          _defaultCoordinates = GeoCoordinates(lat!, lng!);
        });
      } else {
        getRegionsList();
      }
    } else {
      await setMapFlagDataValue('hasOfflineMapData', hasOfflineData);
      await setPlaceNameValue('placeName', placeName);
      getRegionsList();
    }
  }

  void _showDialogs(String title, String message, String option) {
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: general_background_color,
            title: Text(
              title,
              style: const TextStyle(color: general_color),
            ),
            content: Text(
              option == 'e' ? "$error_connection_message\n$message" : message,
              style: const TextStyle(color: description_color),
            ),
            actions: [
              option == 'e'
                  ? const Text("")
                  : TextButton(
                      onPressed: () {
                        option == 'b' ? deleteMapData() : null;

                        _dismissDialog();
                      },
                      child: Text(
                        option == 'i' ? 'Close' : 'Ok',
                        style: const TextStyle(color: general_color),
                      )),
              option == 'b'
                  ? TextButton(
                      onPressed: () {
                        _dismissDialog();
                      },
                      child: const Text(
                        'Close',
                        style: TextStyle(color: general_color),
                      ))
                  : const Text("")
            ],
          );
        });
  }

  _dismissDialog() {
    Navigator.pop(context);
  }

  deleteMapData() {
    _clearMap();

    _mapDownloader.clearPersistentMapStorage((p0) {
      setState(() {
        hasOfflineData = false;
        placeName = "";
        hasRegions = false;
        _defaultCoordinates = null;
      });

      setMapFlagDataValue('hasOfflineMapData', hasOfflineData);
      setPlaceNameValue('placeName', placeName);
      setPlaceNameValue('hasRegionCoords', "");

      checkKeys();
    });
  }

  Future<void> getRegionsList() async {
    print("Downloading the list of available regions.");

    _mapDownloader.getDownloadableRegionsWithLanguageCode(LanguageCode.enUs,
        (MapLoaderError? mapLoaderError, List<Region>? list) {
      if (mapLoaderError != null) {
        _showDialogs("Error", mapLoaderError.toString(), "e");
        return;
      }

      // If error is null, it is guaranteed that the list will not be null.
      _downloadableRegions = list!;

      setState(() {
        childRegions = _downloadableRegions;
        hasRegions = true;
      });
    });
  }

  Future<void> onDownloadMapClicked(String name, RegionId selection) async {
    // For this example we download only one country.
    List<RegionId> regionIDs = [selection];

    setState(() {
      isDownloading = !isDownloading;
    });

    MapDownloaderTask mapDownloaderTask = _mapDownloader.downloadRegions(
        regionIDs,
        DownloadRegionsStatusListener(
                (MapLoaderError? mapLoaderError, List<RegionId>? list) {
              // Handle events from onDownloadRegionsComplete().
              if (mapLoaderError != null) {
                _showDialogs("Error", mapLoaderError.toString(), "e");
                return;
              }

              // If error is null, it is guaranteed that the list will not be null.
              // For this example we downloaded only one hardcoded region.
              String message =
                  "Download Regions Status: Completed $name 100% for ID: " +
                      list!.first.id.toString();
              print(message);
            }, (RegionId regionId, int percentage) {
          // Handle events from onProgress().
          String message =
              "Downloading ${countryName.isNotEmpty ? name + ', ' + countryName : name}." +
                  "\n Progress: " +
                  percentage.toString() +
                  "%.";

          if (percentage == 100) {
            setState(() {
              downloadText = "";
              isDownloading = !isDownloading;
              hasOfflineData = true;
              setMapFlagDataValue('hasOfflineMapData', hasOfflineData);
              placeName = countryName != "" ? name + ', ' + countryName : name;
              setPlaceNameValue('placeName', placeName);

              if (_defaultCoordinates != null) {
                _hereMapController!.camera.lookAtPointWithDistance(
                    _defaultCoordinates!, _distanceToEarthInMeters);
                Future.delayed(const Duration(seconds: 5),
                        () => _initializeOfflineRoutingEngine());
              } else {
                searchPlaceId(placeName);
              }
            });
          } else {
            setState(() {
              downloadText = message;
            });
          }
        }, (MapLoaderError? mapLoaderError) {
          // Handle events from onPause().
          if (mapLoaderError == null) {
            //_showDialog("Info", "The download was paused by the user calling mapDownloaderTask.pause().");
            print(
                "The download was paused by the user calling mapDownloaderTask.pause().");
          } else {
            //_showDialog("Error",
            //"Download regions onPause error. The task tried to often to retry the download: $mapLoaderError");
            print(
                "Download regions onPause error. The task tried to often to retry the download: $mapLoaderError");
          }
        }, () {
          // Hnadle events from onResume().
          //_showDialog("Info", "A previously paused download has been resumed.");
          print("A previously paused download has been resumed.");
        }));

    _mapDownloaderTasks.add(mapDownloaderTask);
  }

  _checkInstallationStatus() {

    // Note that this value will not change during the lifetime of an app.
    PersistentMapStatus persistentMapStatus =
    _mapDownloader.getInitialPersistentMapStatus();
    if (persistentMapStatus == PersistentMapStatus.corrupted ||
        persistentMapStatus == PersistentMapStatus.migrationNeeded) {
      // Something went wrong after the app was closed the last time. It seems the offline map data is
      // corrupted. This can eventually happen, when an ongoing map download was interrupted due to a crash.
      print(
          "PersistentMapStatus: The persistent map data seems to be corrupted. Trying to repair.");

      // Let's try to repair.
      _mapDownloader.repairPersistentMap(
              (PersistentMapRepairError? persistentMapRepairError) {
            if (persistentMapRepairError == null) {
              print(
                  "RepairPersistentMap: Repair operation completed successfully!");

              _checkInstallationStatus();
              return;
            }

            print(
                "RepairPersistentMap: Repair operation failed: $persistentMapRepairError");
          });
    } else if (persistentMapStatus == PersistentMapStatus.invalidPath) {
      //Pending
    } else if (persistentMapStatus == PersistentMapStatus.invalidState) {
      _mapDownloader
          .clearPersistentMapStorage((MapLoaderError? mapLoaderError) {
        if (mapLoaderError == null) {
          print(
              "ClearPersistentMapStorage: Cleaning operation completed successfully!");

          _checkInstallationStatus();
          return;
        }

        print(
            "ClearPersistentMapStorage: Cleaning operation failed: $mapLoaderError");
      });
    } else if (persistentMapStatus == PersistentMapStatus.pendingUpdate) {
      _checkForMapUpdates();
    } else if (persistentMapStatus == PersistentMapStatus.ok) {
      //_getDownloadableRegions();
    }
  }

  void _checkForMapUpdates() {
    _mapUpdater
        .retrieveCatalogsUpdateInfo((mapLoaderError, catalogUpdateInfoList) {
      if (mapLoaderError != null) {
        _showDialogs("Error", mapLoaderError.toString(), "e");
        return;
      }

      if (catalogUpdateInfoList!.isEmpty) {
        print(
            "MapUpdateCheck: No map update available. Latest versions are already installed.");

        _checkInstallationStatus();
      }

      // Usually, only one global catalog is available that contains regions for the whole world.
      // For some regions like Japan only a base map is available, by default.
      // If your company has an agreement with HERE to use a detailed Japan map, then in this case you
      // can install and use a second catalog that references the detailed Japan map data.
      // All map data is part of downloadable regions. A catalog contains references to the
      // available regions. The map data for a region may differ based on the catalog that is used
      // or on the version that is downloaded and installed.
      for (CatalogUpdateInfo catalogUpdateInfo in catalogUpdateInfoList) {
        print(
            "CatalogUpdateCheck - Catalog name:${catalogUpdateInfo.installedCatalog.catalogIdentifier.hrn}");
        print(
            "CatalogUpdateCheck - Installed map version:${catalogUpdateInfo.installedCatalog.catalogIdentifier.version}");
        print(
            "CatalogUpdateCheck - Latest available map version:${catalogUpdateInfo.latestVersion}");

        if (_mapUpdateTasks.isEmpty) {
          setState(() {
            isDownloading = true;
          });

          _performMapUpdate(catalogUpdateInfo);
        }
      }
    });
  }

  // Downloads and installs map updates for any of the already downloaded regions.
  // Note that this example only shows how to download one region.
  void _performMapUpdate(CatalogUpdateInfo catalogUpdateInfo) {
    // This method conveniently updates all installed regions if an update is available.
    // Optionally, you can use the MapUpdateTask to pause / resume or cancel the update.
    setState(() {
      isDownloading = !isDownloading;
    });

    CatalogUpdateTask mapUpdateTask = _mapUpdater.updateCatalog(
        catalogUpdateInfo,
        CatalogUpdateProgressListener((RegionId regionId, int percentage) {
          // Handle events from onProgress().
          print(
              "MapUpdate: Downloading and installing a map update. Progress for ${regionId.id}: $percentage%.");

          if (percentage == 100) {
            setState(() {
              downloadText = "";
              isDownloading = !isDownloading;
            });
            if (_defaultCoordinates != null) {
              _hereMapController!.camera.lookAtPointWithDistance(
                  _defaultCoordinates!, _distanceToEarthInMeters);
              Future.delayed(const Duration(seconds: 5),
                      () => _initializeOfflineRoutingEngine());
            } else {
              searchPlaceId(placeName);
            }
          } else {
            setState(() {
              downloadText =
              "Downloading and installing a map update for $placeName: $percentage%.";
            });
          }
        }, (MapLoaderError? mapLoaderError) {
          // Handle events from onPause().
          if (mapLoaderError == null) {
            print(
                "MapUpdate:  The map update was paused by the user calling mapUpdateTask.pause().");
            setState(() {
              isDownloading = !isDownloading;
            });
          } else {
            setState(() {
              isDownloading = !isDownloading;
              _mapUpdateTasks.clear();
            });

            return;
          }
        }, (MapLoaderError? mapLoaderError) {
          // Handle events from onComplete().
          if (mapLoaderError != null) {
            _showDialogs("Error", mapLoaderError.toString(), "e");
            setState(() {
              isDownloading = !isDownloading;
              _mapUpdateTasks.clear();
            });
            return;
          }
          print(
              "MapUpdate: One or more map update has been successfully installed.");

          _checkInstallationStatus();

          // It is recommend to call now also `getDownloadableRegions()` to update
          // the internal catalog data that is needed to download, update or delete
          // existing `Region` data. It is required to do this at least once
          // before doing a new download, update or delete operation.
        }, () {
          // Handle events from onResume():
          print("MapUpdate: A previously paused map update has been resumed.");
        }));

    _mapUpdateTasks.add(mapUpdateTask);
  }

  Future<void> searchPlaceId(String place) async {
    print(place);

    var url = Uri.parse(
        "https://autocomplete.search.hereapi.com/v1/autocomplete?apiKey=$API_KEY&q=$place");

    var result = await http.get(url).then((http.Response response) {
      final String res = response.body;
      final int statusCode = response.statusCode;

      if (statusCode < 200 || statusCode > 400) {
        throw Exception("Error while fetching data");
      }
      return jsonDecode(res);
    });

    print(result);

    print("${result["items"][0]["id"]}");

    String? placeId = "${result["items"][0]["id"]}";

    await searchPlaceCoords(placeId);

    //_hereMapController!.camera.lookAtPointWithDistance(GeoCoordinates(lat!, lng!), 250000);
  }

  Future<void> searchPlaceCoords(String placeId) async {
    print(placeId);

    var url = Uri.parse(
        "https://lookup.search.hereapi.com/v1/lookup?apiKey=$API_KEY&id=$placeId");

    var result = await http.get(url).then((http.Response response) {
      final String res = response.body;
      final int statusCode = response.statusCode;

      if (statusCode < 200 || statusCode > 400) {
        throw Exception("Error while fetching data");
      }
      return jsonDecode(res);
    });

    print(result);

    print("${result["position"]["lat"]}, ${result["position"]["lng"]}");

    double? lat = result["position"]["lat"];
    double? lng = result["position"]["lng"];

    setState(() {
      _defaultCoordinates = GeoCoordinates(lat!, lng!);
      setPlaceNameValue('hasRegionCoords',
          "${_defaultCoordinates!.latitude},${_defaultCoordinates!.longitude}");
    });

    _hereMapController!.camera.lookAtPointWithDistance(
        _defaultCoordinates!, _distanceToEarthInMeters);

    Future.delayed(
        const Duration(seconds: 5), () => _initializeOfflineRoutingEngine());
  }

  void showLoadingIndicator() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8.0))),
                backgroundColor: general_background_color,
                content: Container(
                    padding: EdgeInsets.all(16),
                    color: general_background_color,
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                              child: SizedBox(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    backgroundColor: Colors.transparent,
                                    color: general_color,
                                  ),
                                  width: 32,
                                  height: 32),
                              padding: EdgeInsets.only(bottom: 16)),
                          const Padding(
                              child: Text(
                                'Please wait …',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                              padding: EdgeInsets.only(top: 10, bottom: 10)),
                          Text(
                            downloadText,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            textAlign: TextAlign.center,
                          )
                        ]))));
      },
    );
  }

  _stopGuidance() {
    _locationSimulator.stop();
    // Leaves guidance (if it was running) and enables tracking mode. The camera may optionally follow, see toggleTracking().
    _visualNavigator.route = null;

    /*_visualNavigator.stopRendering().whenComplete(() {
      _hereMapController?.camera.lookAtPointWithGeoOrientationAndDistance(
          _defaultCoordinates!, newOrientation, _distanceToEarthInMeters);
    });*/

    _visualNavigator.stopRendering();

    _hereMapController?.camera.lookAtPointWithGeoOrientationAndDistance(
        _defaultCoordinates!, newOrientation, _distanceToEarthInMeters);

    setState(() {
      stopNavigation = false;
      enableResetCameraPosition = true;
      showRouteInfo = true;
      showInfoNavigation = false;
      enableReset = true;
      navigationInfo = '';
    });

    _setTapGestureHandler();
    _setLongPressGestureHandler();
  }

  void _setTapGestureHandler() {
    _hereMapController?.gestures.tapListener =
        TapListener((Point2D touchPoint) {
      GeoCoordinates? geoCoordinates =
          _hereMapController?.viewToGeoCoordinates(touchPoint);
      if (geoCoordinates == null) {
        return;
      }
      _addPoiMapMarker(geoCoordinates, false, putFirstMarker);
    });
  }

  void _setLongPressGestureHandler() {
    _hereMapController?.gestures.longPressListener =
        LongPressListener((GestureState gestureState, Point2D touchPoint) {
      if (gestureState == GestureState.begin && _mapMarkerList.isNotEmpty) {
        GeoCoordinates? geoCoordinates =
            _hereMapController?.viewToGeoCoordinates(touchPoint);
        if (geoCoordinates == null) {
          return;
        }
        _addPoiMapMarker(geoCoordinates, true, false);
      }
    });
  }

  Future<MapMarker> _addPoiMapMarker(
      GeoCoordinates geoCoordinates, bool isFinish, bool isBegin) async {
    // Reuse existing MapImage for new map markers.
    Uint8List imagePixelData;

    if (isFinish) {
      imagePixelData = await _loadFileAsUint8List('destination_marker.png');
    } else if (isBegin) {
      imagePixelData = await _loadFileAsUint8List('start_marker.png');
    } else {
      imagePixelData = await _loadFileAsUint8List('map_marker.png');
    }

    _poiMapImage =
        MapImage.withPixelDataAndImageFormat(imagePixelData, ImageFormat.png);

    MapMarker mapMarker = MapMarker(geoCoordinates, _poiMapImage!);

    flagMarkers > 0
        ? null
        : _hereMapController?.mapScene.addMapMarker(mapMarker);

    flagMarkers > 0 ? null : _mapMarkerList.add(mapMarker);

    isFinish ? addRoute() : null;

    setState(() {
      putFirstMarker = false;
      enableReset = true;
      isFinish ? flagMarkers = 1 : null;
    });

    return mapMarker;
  }

  Future<Uint8List> _loadFileAsUint8List(String fileName) async {
    // The path refers to the assets directory as specified in pubspec.yaml.
    ByteData fileData = await rootBundle.load('assets/' + fileName);
    return Uint8List.view(fileData.buffer);
  }

  void _initializeOfflineRoutingEngine() {
    try {
      _offlineRoutingEngine = OfflineRoutingEngine();

      Fluttertoast.showToast(
        msg: initial_message,
        toastLength: Toast.LENGTH_LONG,
      );

      Future.delayed(const Duration(seconds: 5), () {
        _setTapGestureHandler();
        _setLongPressGestureHandler();
      });
    } on InstantiationException {
      throw ("Initialization of RoutingEngine failed.");
    }
  }

  void addRoute() {
    Fluttertoast.showToast(
      msg: loading_route_message,
    );

    List<Waypoint> waypoints = [];

    clearRoute();

    for (var markers in _mapMarkerList) {
      waypoints.add(Waypoint.withDefaults(GeoCoordinates(
          markers.coordinates.latitude, markers.coordinates.longitude)));
    }

    _offlineRoutingEngine
        ?.calculateCarRoute(waypoints, CarOptions.withDefaults(),
            (RoutingError? routingError, List<here.Route>? routeList) async {
      if (routingError == null) {
        // When error is null, it is guaranteed that the list is not empty.
        route = routeList!.first;

        _showRouteOnMap(route);
      } else {
        var error = routingError.toString();
        //_showDialog('Error', 'Error while calculating a route: $error');
        print('Error while calculating a route: $error');

        Fluttertoast.showToast(
          msg: error_route_message,
        );
      }
    });
  }

  void _showRouteDetails(here.Route route) {
    int estimatedTravelTimeInSeconds = route.duration.inSeconds;
    int lengthInMeters = route.lengthInMeters;

    setState(() {
      travelTime = _formatTime(estimatedTravelTimeInSeconds);
      travelLength = _formatLength(lengthInMeters);
    });

    String routeDetails =
        'Travel Time: ' + travelTime + ', Length: ' + travelLength;
    print(routeDetails);
  }

  // A route may contain several warnings, for example, when a certain route option could not be fulfilled.
  // An implementation may decide to reject a route if one or more violations are detected.
  void _logRouteViolations(here.Route route) {
    for (var section in route.sections) {
      for (var notice in section.sectionNotices) {
        print("This route contains the following warning: " +
            notice.code.toString());
      }
    }
  }

  _showRouteOnMap(here.Route route) {
    // Show route as polyline.
    GeoPolyline routeGeoPolyline = route.geometry;

    double widthInPixels = 15;
    MapPolyline routeMapPolyline =
        MapPolyline(routeGeoPolyline, widthInPixels, general_color);

    _hereMapController?.mapScene.addMapPolyline(routeMapPolyline);
    _mapPolylines.add(routeMapPolyline);
    setState(() {
      enableNavigation = true;
      showRouteInfo = true;
    });
    _showRouteDetails(route);
    _logRouteViolations(route);
  }

  String _formatTime(int sec) {
    int hours = sec ~/ 3600;
    int minutes = (sec % 3600) ~/ 60;

    return '$hours hrs : $minutes min';
  }

  String _formatLength(int meters) {
    int kilometers = meters ~/ 1000;
    int remainingMeters = meters % 1000;

    return '$kilometers.$remainingMeters km';
  }

  _startGuidance(here.Route route) {
    try {
      // Without a route set, this starts tracking mode.
      _visualNavigator = navigation.VisualNavigator();
    } on InstantiationException {
      throw Exception("Initialization of VisualNavigator failed.");
    }

    // This enables a navigation view including a rendered navigation arrow.
    _visualNavigator.startRendering(_hereMapController!);

    // Hook in one of the many listeners. Here we set up a listener to get instructions on the maneuvers to take while driving.
    // For more details, please check the "navigation_app" example and the Developer's Guide.
    _visualNavigator.maneuverNotificationListener =
        navigation.ManeuverNotificationListener((String maneuverText) {
      print("ManeuverNotifications: $maneuverText");
      setState(() {
        navigationInfo = maneuverText;
      });
    });

    // Set a route to follow. This leaves tracking mode.
    _visualNavigator.route = route;

    // VisualNavigator acts as LocationListener to receive location updates directly from a location provider.
    // Any progress along the route is a result of getting a new location fed into the VisualNavigator.
    _setupLocationSource(_visualNavigator, route);
  }

  _setupLocationSource(LocationListener locationListener, here.Route route) {
    try {
      // Provides fake GPS signals based on the route geometry.
      _locationSimulator = navigation.LocationSimulator.withRoute(
          route, navigation.LocationSimulatorOptions.withDefaults());

      _locationSimulator.listener = locationListener;
      _locationSimulator.start();

      _hereMapController?.gestures.tapListener = null;
      _hereMapController?.gestures.longPressListener = null;

      setState(() {
        stopNavigation = true;
        enableReset = false;
        enableResetCameraPosition = false;
        showRouteInfo = false;
        showInfoNavigation = true;
      });
    } on InstantiationException {
      throw Exception("Initialization of LocationSimulator failed.");
    }
  }

  void _clearMap() {
    for (var mapMarker in _mapMarkerList) {
      _hereMapController?.mapScene.removeMapMarker(mapMarker);
    }

    _mapMarkerList.clear();

    clearRoute();

    setState(() {
      putFirstMarker = true;
      enableReset = false;
      flagMarkers = 0;
      travelTime = "";
      travelLength = "";
    });
  }

  void clearRoute() {
    for (var mapPolyline in _mapPolylines) {
      _hereMapController?.mapScene.removeMapPolyline(mapPolyline);
    }
    _mapPolylines.clear();
    setState(() {
      enableNavigation = false;
      showRouteInfo = false;
    });
  }
}
