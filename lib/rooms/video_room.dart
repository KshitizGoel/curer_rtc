import 'dart:async';

import 'package:agora_rtc_engine/rtc_engine.dart';
import 'package:chatapploydlab/Controllers/fb_messaging.dart';
import 'package:chatapploydlab/utils/agora_utils.dart';
import 'package:chatapploydlab/utils/call.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agora_rtc_engine/rtc_local_view.dart' as RtcLocalView;
import 'package:agora_rtc_engine/rtc_remote_view.dart' as RtcRemoteView;
import '../Controllers/fb_firestore.dart';
import '../subWidgets/local_notification_view.dart';

class VideoRoom extends StatefulWidget {
  String myID,
      myName,
      myImageUrl,
      selectedUserToken,
      selectedUserID,
      chatID,
      selectedUserName,
      selectedUserThumbnail,
      channelName;
  final ClientRole role;

  VideoRoom(
      this.myID,
      this.myName,
      this.myImageUrl,
      this.selectedUserToken,
      this.selectedUserID,
      this.chatID,
      this.selectedUserName,
      this.selectedUserThumbnail,
      {this.channelName,
      this.role});

  @override
  _VideoRoomState createState() => _VideoRoomState();
}

class _VideoRoomState extends State<VideoRoom>
    with WidgetsBindingObserver, LocalNotificationView {
  final TextEditingController _msgTextController = new TextEditingController();
  final ScrollController _chatListController = ScrollController();
  String messageType = 'text';
  int chatListLength = 20;
  final _users = <int>[];
  final _infoStrings = <String>[];
  bool muted = false;
  RtcEngine _engine;
  Map<String, Call> calls = {};

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('didChangeAppLifecycleState');
    setState(() {
      switch (state) {
        case AppLifecycleState.resumed:
          FBCloudStore.instance
              .updateMyChatListValues(widget.myID, widget.chatID, true);
          print('AppLifecycleState.resumed');
          break;
        case AppLifecycleState.inactive:
          print('AppLifecycleState.inactive');
          FBCloudStore.instance
              .updateMyChatListValues(widget.myID, widget.chatID, false);
          break;
        case AppLifecycleState.paused:
          print('AppLifecycleState.paused');
          FBCloudStore.instance
              .updateMyChatListValues(widget.myID, widget.chatID, false);
          break;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FBCloudStore.instance
        .updateMyChatListValues(widget.myID, widget.chatID, true);

    if (mounted) {
      isShowLocalNotification = true;
      _savedChatId(widget.chatID);
      checkLocalNotification(localNotificationAnimation, widget.chatID);
    }

    initialize();
  }

  Future<void> initialize() async {
    if (APP_ID.isEmpty) {
      setState(() {
        _infoStrings.add(
          'APP_ID missing, please provide your APP_ID in settings.dart',
        );
        _infoStrings.add('Agora Engine is not starting');
      });
      return;
    }

    await _initAgoraRtcEngine();
    _addAgoraEventHandlers();
    // ignore: deprecated_member_use
    await _engine.enableWebSdkInteroperability(true);
    VideoEncoderConfiguration configuration = VideoEncoderConfiguration();
    configuration.dimensions = VideoDimensions(1920, 1080);
    await _engine.setVideoEncoderConfiguration(configuration);
    await _engine.joinChannel(Token, widget.channelName, null, 0);
  }

  Future<void> _initAgoraRtcEngine() async {
    _engine = await RtcEngine.create(APP_ID);
    await _engine.enableVideo();
    await _engine.setChannelProfile(ChannelProfile.Communication);
    await _engine.setClientRole(widget.role);
  }

  void _addAgoraEventHandlers() {
    _engine.setEventHandler(RtcEngineEventHandler(error: (code) {
      setState(() {
        final info = 'onError: $code';
        _infoStrings.add(info);
      });
    }, joinChannelSuccess: (channel, uid, elapsed) {
      setState(() {
        final info = 'onJoinChannel: $channel, uid: $uid';
        _infoStrings.add(info);
      });
    }, leaveChannel: (stats) {
      setState(() {
        _infoStrings.add('onLeaveChannel');
        _users.clear();
      });
    }, userJoined: (uid, elapsed) {
      setState(() {
        final info = 'userJoined: $uid';
        _infoStrings.add(info);
        _users.add(uid);
      });
    }, userOffline: (uid, elapsed) {
      setState(() {
        final info = 'userOffline: $uid';
        _infoStrings.add(info);
        _users.remove(uid);
      });
    }, firstRemoteVideoFrame: (uid, width, height, elapsed) {
      setState(() {
        final info = 'firstRemoteVideo: $uid ${width}x $height';
        _infoStrings.add(info);
      });
    }));
  }

  void localNotificationAnimation(List<dynamic> data) {
    if (mounted) {
      setState(() {
        if (data[1] == 1.0) {
          localNotificationData = data[0];
        }
        localNotificationAnimationOpacity = data[1] as double;
      });
    }
  }

  Future<void> _savedChatId(String value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("inRoomChatId", value);
  }

  @override
  void dispose() {
    isShowLocalNotification = false;
    _users.clear();
    _engine.leaveChannel();
    _engine.destroy();
    FBCloudStore.instance
        .updateMyChatListValues(widget.myID, widget.chatID, false);
    _savedChatId("");
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              "Video Chat Room with - ${widget.selectedUserName}",
              style: TextStyle(fontSize: 15),
            ),
            centerTitle: true,
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
          floatingActionButton: FloatingActionButton(
            child: InkWell(
              onTap: () {
                sendNotifications();
              },
              child: Icon(
                Icons.add,
                color: Colors.white,
              ),
            ),
          ),
          body: Stack(
            children: <Widget>[
              _viewRows(),
              _panel(),
              _toolbar(),
            ],
          ),
        ),
      ),
    );
    // );
  }

  /// All the Widgets for Video Calling......

  Widget _viewRows() {
    final views = _getRenderViews();
    switch (views.length) {
      case 1:
        return Container(
            child: Column(
          children: <Widget>[_videoView(views[0])],
        ));
      case 2:
        return Container(
            child: Column(
          children: <Widget>[
            _expandedVideoRow([views[0]]),
            _expandedVideoRow([views[1]])
          ],
        ));
      case 3:
        return Container(
            child: Column(
          children: <Widget>[
            _expandedVideoRow(views.sublist(0, 2)),
            _expandedVideoRow(views.sublist(2, 3))
          ],
        ));
      case 4:
        return Container(
            child: Column(
          children: <Widget>[
            _expandedVideoRow(views.sublist(0, 2)),
            _expandedVideoRow(views.sublist(2, 4))
          ],
        ));
      default:
    }
    return Container();
  }

  Widget _toolbar() {
    if (widget.role == ClientRole.Audience) return Container();
    return Container(
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          RawMaterialButton(
            onPressed: _onToggleMute,
            child: Icon(
              muted ? Icons.mic_off : Icons.mic,
              color: muted ? Colors.white : Colors.blueAccent,
              size: 20.0,
            ),
            shape: CircleBorder(),
            elevation: 2.0,
            fillColor: muted ? Colors.blueAccent : Colors.white,
            padding: const EdgeInsets.all(12.0),
          ),
          RawMaterialButton(
            onPressed: () => _onCallEnd(context),
            child: Icon(
              Icons.call_end,
              color: Colors.white,
              size: 35.0,
            ),
            shape: CircleBorder(),
            elevation: 2.0,
            fillColor: Colors.redAccent,
            padding: const EdgeInsets.all(15.0),
          ),
          RawMaterialButton(
            onPressed: _onSwitchCamera,
            child: Icon(
              Icons.switch_camera,
              color: Colors.blueAccent,
              size: 20.0,
            ),
            shape: CircleBorder(),
            elevation: 2.0,
            fillColor: Colors.white,
            padding: const EdgeInsets.all(12.0),
          ),
        ],
      ),
    );
  }

  // Info panel to show logs
  Widget _panel() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: ListView.builder(
            reverse: true,
            itemCount: _infoStrings.length,
            itemBuilder: (BuildContext context, int index) {
              if (_infoStrings.isEmpty) {
                return null;
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 3,
                  horizontal: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 2,
                          horizontal: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.yellowAccent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          _infoStrings[index],
                          style: TextStyle(color: Colors.blueGrey),
                        ),
                      ),
                    )
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Filler Widgets

  List<Widget> _getRenderViews() {
    final List<StatefulWidget> list = [];
    if (widget.role == ClientRole.Broadcaster) {
      list.add(RtcLocalView.SurfaceView());
    }
    _users.forEach((int uid) => list.add(RtcRemoteView.SurfaceView(uid: uid)));
    return list;
  }

  Widget _videoView(view) {
    return Expanded(child: Container(child: view));
  }

  Widget _expandedVideoRow(List<Widget> views) {
    final wrappedViews = views.map<Widget>(_videoView).toList();
    return Expanded(
      child: Row(
        children: wrappedViews,
      ),
    );
  }

  /// Filler functions and methods

  void _onCallEnd(BuildContext context) {
    Navigator.pop(context);
  }

  void _onToggleMute() {
    setState(() {
      muted = !muted;
    });
    _engine.muteLocalAudioStream(muted);
  }

  void _onSwitchCamera() {
    _engine.switchCamera();
  }

  Future<void> sendNotifications() async {
    try {


      /// !!!!!! Here we have to implement the function !!!!!!!

      await NotificationController.instance.sendCallNotification(
          0,
          messageType,
          'Hello there!! Please pick up the call!!!!\nYour consultation is in process!',
          widget.myName,
          widget.chatID,
          widget.selectedUserToken,
          widget.myImageUrl);
    } catch (e) {
      print(e.message);
    }
  }


}
