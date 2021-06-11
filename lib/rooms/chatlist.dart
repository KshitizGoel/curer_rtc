import 'dart:async';

import 'package:agora_rtc_engine/rtc_engine.dart';
import 'package:chatapploydlab/rooms/video_room.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../Controllers/fb_messaging.dart';
import '../Controllers/image_controller.dart';
import '../Controllers/utils.dart';
import 'chatroom.dart';
import '../subWidgets/common_widgets.dart';
import '../subWidgets/local_notification_view.dart';

class ChatList extends StatefulWidget {
  ChatList(this.myID, this.myName, this.myImageUrl);

  String myID;
  String myName;
  String myImageUrl;

  @override
  _ChatList createState() => _ChatList();
}

class _ChatList extends State<ChatList> with LocalNotificationView {
  ClientRole _role = ClientRole.Broadcaster;

  @override
  void initState() {
    super.initState();
    NotificationController.instance.updateTokenToServer();
    if (mounted) {
      checkLocalNotification(localNotificationAnimation, "");
    }
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat App - Chat List'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, AsyncSnapshot<QuerySnapshot> userSnapshot) {
            if (!userSnapshot.hasData) return loadingCircleForFB();
            return countChatListUsers(widget.myID, userSnapshot) > 0
                ? Stack(
                    children: [
                      ListView(
                          children: userSnapshot.data.docs.map((userData) {
                        if (userData['userId'] == widget.myID) {
                          return Container();
                        } else {
                          return StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(widget.myID)
                                  .collection('chatlist')
                                  .where('chatWith',
                                      isEqualTo: userData['userId'])
                                  .snapshots(),
                              builder: (context, chatListSnapshot) {
                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: ImageController.instance
                                        .cachedImage(userData['userImageUrl']),
                                  ),
                                  title: Text(userData['name']),
                                  subtitle: Text((chatListSnapshot.hasData &&
                                          chatListSnapshot.data.docs.length > 0)
                                      ? chatListSnapshot.data.docs[0]
                                          ['lastChat']
                                      : userData['intro']),
                                  trailing: Stack(
                                    children: [
                                      Container(
                                        decoration : BoxDecoration(
                                          color: Colors.orange[700],
                                          borderRadius: BorderRadius.circular(30)
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(3),
                                          child : IconButton(
                                          onPressed: () {
                                            _moveToVideoCallRoom(
                                                userData['FCMToken'],
                                                userData['userId'],
                                                userData['name'],
                                                userData['userImageUrl']);
                                          },
                                          icon: Icon(
                                            Icons.video_call,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),)
                                    ],
                                  ),
                                  onTap: () => _moveToChatRoom(
                                      userData['FCMToken'],
                                      userData['userId'],
                                      userData['name'],
                                      userData['userImageUrl']),
                                );
                              });
                        }
                      }).toList()),
                      localNotificationCard(size)
                    ],
                  )
                : Container(
                    child: Center(
                        child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.forum,
                          color: Colors.grey[700],
                          size: 64,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Text(
                            'There are no users except you.\nPlease use other devices to chat.',
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey[700]),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )),
                  );
          }),
    );
  }

  Future<void> _moveToChatRoom(selectedUserToken, selectedUserID,
      selectedUserName, selectedUserThumbnail) async {
    try {
      String chatID = makeChatId(widget.myID, selectedUserID);
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => ChatRoom(
                  widget.myID,
                  widget.myName,
                  widget.myImageUrl,
                  selectedUserToken,
                  selectedUserID,
                  chatID,
                  selectedUserName,
                  selectedUserThumbnail)));
    } catch (e) {
      print(e.message);
    }
  }

  Future<void> _moveToVideoCallRoom(selectedUserToken, selectedUserID,
      selectedUserName, selectedUserThumbnail) async {
    try {
      await _handleCameraAndMic(Permission.camera);
      await _handleCameraAndMic(Permission.microphone);
      String chatID = makeChatId(widget.myID, selectedUserID);
      Navigator.push(
          context,
          MaterialPageRoute(

              //Mention the channelName and role

              builder: (context) => VideoRoom(
                    widget.myID,
                    widget.myName,
                    widget.myImageUrl,
                    selectedUserToken,
                    selectedUserID,
                    chatID,
                    selectedUserName,
                    selectedUserThumbnail,
                    role: _role,
                    channelName: 'Video Testing',
                  )));
    } catch (e) {
      print(e.message);
    }
  }

  Future<void> _handleCameraAndMic(Permission permission) async {
    final status = await permission.request();
    print(status);
  }
}
