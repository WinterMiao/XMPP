//
//  XMPPManager.m
//  0834XMPP
//
//  Created by 郑建文 on 15/11/24.
//  Copyright © 2015年 Lanou. All rights reserved.
//

#import "XMPPManager.h"
#import "AppDelegate.h"
#import "JDStatusBarNotification.h"

typedef enum : NSUInteger {
    Connect4Login,
    Connect4Register,
} ConnectType;//链接目的

@interface XMPPManager ()<XMPPStreamDelegate,XMPPRosterDelegate>

//记录登陆密码
@property (nonatomic,copy) NSString * loginPassword;
//记录注册密码
@property (nonatomic,copy) NSString * regPassword;

//记录一下连接的目的
@property (nonatomic,assign) ConnectType connectType;

@end

@implementation XMPPManager

static XMPPManager * manager = nil;

+ (XMPPManager *)sharedManager{
    //gcd 创建单例对象
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[XMPPManager alloc] init];
       
    });
    return manager;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        //--------------配置通信管道-----------
        self.stream = [[XMPPStream alloc] init];
        //设置通信管道个目标服务器地址
        _stream.hostName = kHostName;
        //设置目标服务器的xmpp server的端口
        _stream.hostPort = kHostPort;
        
        //设置代理,在主线程里面触发回调事件
        [_stream addDelegate:self delegateQueue:dispatch_get_main_queue()];
        
        
        //-------------用户花名册---------------------
        //xmpproster 用来处理和用户相关的一切操作(获取好友列表,添加好友,接收好友请求,同意添加好友,拒绝添加好友)
        
        //xmpp 为我们提供的一个coredata 存储器
        XMPPRosterCoreDataStorage *xrcds = [XMPPRosterCoreDataStorage sharedInstance];
        
        //创建roster 花名册时,需要给花名册指定一个数据存储的地方(有就是XMPPRosterCoreDataStorage)
        self.roster = [[XMPPRoster alloc] initWithRosterStorage:xrcds dispatchQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0)];
        
        //在通讯管道中激活花名册
        //这时就可以通过通讯管道去给服务器发送请求了.
        //然后roster 的 消息都通过 stream 间接的发给服务器
        [self.roster activate:self.stream];
        
        //添加代理
        [self.roster addDelegate:self delegateQueue:dispatch_get_main_queue()];
        
        
        //----------------初始化 XMPPMessageArchiving-----
        
        //xmppMessageArchiving 主要功能: 1. 通过通讯管道获取到服务器发送过来的消息,2.讲消息存储到指定的XMPPMessageArchivingCoreDataStorage
        
        //xmpp 为我们提 供的一个存储聊天消息的coredata仓库
        XMPPMessageArchivingCoreDataStorage *xmacds = [XMPPMessageArchivingCoreDataStorage sharedInstance];
        
        //初始化时,需要给这个归档类指定一个存储仓库.
        self.messageArchiving = [[XMPPMessageArchiving alloc] initWithMessageArchivingStorage:xmacds dispatchQueue:dispatch_get_main_queue()];
        
        //在通讯管道中激活消息归档类
        [self.messageArchiving activate:self.stream];
        
        //添加代理
        [self.messageArchiving addDelegate:self delegateQueue:dispatch_get_main_queue()];
        
        //让我们创建的上下文直接等于消息归档类存储的coredata仓库的上下文
        self.context = xmacds.mainThreadManagedObjectContext;
    }
    return self;
}

//登陆
- (void)xmppManagerLoginWithUserName:(NSString *)userName password:(NSString *)password{
    //记录登陆密码
    self.loginPassword = password;
    //记录链接的目的
    self.connectType = Connect4Login;
    
    [self connectWithUserName:userName];
}
//注册
- (void)xmppManagerRegisterWithUserName:(NSString *)username password:(NSString *)password{
    //记录注册密码
    self.regPassword = password;
    //记录链接的目的
    self.connectType = Connect4Register;
    //链接服务器
    [self connectWithUserName:username];
}

//xmpp 协议规定,链接时可以不告诉服务器密码,但是一定要告诉服务器是谁在链接它
- (void)connectWithUserName:(NSString *)userName{
    //根据一个用户名构造一个xmppjid
    XMPPJID *myjid = [XMPPJID jidWithUser:userName domain:kDomin resource:kResource];
    //设置通信管道的jid
    _stream.myJID = myjid;
    //链接服务器
    [self connectToServer];
}
//XMPPJid - xmpp系统中的用户类
//链接服务器
- (void)connectToServer{
    
    //先判断一下是否链接过服务器
    if ([_stream isConnected]) {
        NSLog(@"已经链接过了,先断开,再链接");
        [_stream disconnect];
    }
    //发起链接
    BOOL result = [_stream connectWithTimeout:30 error:nil];
    if (result) {
//        NSLog(@"链接服务器成功");
    }else{
//        NSLog(@"链接服务器失败");
    }
}

#pragma mark - XMPPStreamDelegate
//链接服务器成功的回调方法
- (void)xmppStreamDidConnect:(XMPPStream *)sender{
    NSLog(@"链接服务器成功-回调方法");
    switch (self.connectType) {
        case Connect4Login:
            //在链接成功后发起登陆事件
            [_stream authenticateWithPassword:self.loginPassword error:nil];
            break;
        case Connect4Register:
            //在链接成功后进行注册
            [_stream registerWithPassword:self.regPassword error:nil];
            break;
        default:
            NSLog(@"一定是忘记 记录链接目的了"); 
            break;
    }
}
//链接超时的回调方法
- (void)xmppStreamConnectDidTimeout:(XMPPStream *)sender{
    NSLog(@"链接超时--回调方法");
}
//断开链接(或者链接失败)的回调方法
- (void)xmppStreamDidDisconnect:(XMPPStream *)sender withError:(NSError *)error{
    NSLog(@"断开链接--回调方法");
    if (error) {
        NSLog(@"%@",error);
    }
    //离线消息(下线通知)
    XMPPPresence *presence = [XMPPPresence presenceWithType:@"unavailable"];
    //发送离线通知
    [_stream sendElement:presence];
}

//登陆成功的回调事件
- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender{
//    NSLog(@"登陆成功");
    
    //出席消息(上线通知)
    XMPPPresence *presence = [XMPPPresence presenceWithType:@"available"];
    //发送上线通知
    [_stream sendElement:presence];
}
//登陆失败的回调事件
- (void)xmppStream:(XMPPStream *)sender didNotAuthenticate:(DDXMLElement *)error{
    NSLog(@"登陆失败 : %@",error);
}

//注册成功的回调事件
- (void)xmppStreamDidRegister:(XMPPStream *)sender{
    NSLog(@"注册成功");
}
//注册失败回调事件
- (void)xmppStream:(XMPPStream *)sender didNotRegister:(DDXMLElement *)error{
    NSLog(@"注册失败 ,error:%@",error);
}

#pragma mark - XMPPRosterDelegate

- (void)xmppRoster:(XMPPRoster *)sender didReceiveRosterItem:(DDXMLElement *)item{
    
}

//接收到好友请求
- (void)xmppRoster:(XMPPRoster *)sender didReceivePresenceSubscriptionRequest:(XMPPPresence *)presence{
    
    
//    NSString *message = [NSString stringWithFormat:@"%@请求添加你为好友",presence.from.user];
//    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"好友请求" message:message preferredStyle:UIAlertControllerStyleAlert];
//    [[[[UIApplication sharedApplication].delegate window] rootViewController] showViewController:ac sender:nil];
}

-(void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message{
    [JDStatusBarNotification showWithStatus:@"收到一条消息" dismissAfter:2];  
}

@end
