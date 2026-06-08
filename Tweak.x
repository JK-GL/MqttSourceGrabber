// MqttSourceGrabber2.x
// Hook NSUserDefaults 找凭据存储位置

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <objc/runtime.h>

@interface MqttLogManager : NSObject
@property (nonatomic, strong) NSMutableArray *logs;
@property (nonatomic, copy) void (^onNewLog)(NSString *log);
+ (instancetype)sharedInstance;
- (void)addLog:(NSString *)log;
@end

@implementation MqttLogManager

static MqttLogManager *_instance = nil;

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[MqttLogManager alloc] init];
        _instance.logs = [NSMutableArray array];
    });
    return _instance;
}

- (void)addLog:(NSString *)log {
    @synchronized (self.logs) {
        [self.logs addObject:log];
        if (self.logs.count > 500) {
            [self.logs removeObjectAtIndex:0];
        }
    }
    if (self.onNewLog) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.onNewLog(log);
        });
    }
    NSLog(@"%@", log);
}

@end

@interface MqttLogViewController : UITableViewController
@property (nonatomic, strong) NSArray *logs;
@end

@implementation MqttLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"MQTT 凭据来源";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(close)];
    
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(clearLogs)],
        [[UIBarButtonItem alloc] initWithTitle:@"导出"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(shareLogs)]
    ];
    
    @synchronized ([MqttLogManager sharedInstance].logs) {
        self.logs = [[MqttLogManager sharedInstance].logs copy];
    }
    
    __weak typeof(self) weakSelf = self;
    [MqttLogManager sharedInstance].onNewLog = ^(NSString *log) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            @synchronized ([MqttLogManager sharedInstance].logs) {
                strongSelf.logs = [[MqttLogManager sharedInstance].logs copy];
            }
            [strongSelf.tableView reloadData];
        }
    };
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)clearLogs {
    @synchronized ([MqttLogManager sharedInstance].logs) {
        [[MqttLogManager sharedInstance].logs removeAllObjects];
        self.logs = @[];
    }
    [self.tableView reloadData];
}

- (void)shareLogs {
    @synchronized ([MqttLogManager sharedInstance].logs) {
        NSString *allLogs = [[MqttLogManager sharedInstance].logs componentsJoinedByString:@"\n"];
        
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"MQTT_source.txt"];
        [allLogs writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        NSURL *fileURL = [NSURL fileURLWithPath:tempPath];
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] 
            initWithActivityItems:@[fileURL] 
            applicationActivities:nil];
        
        [self presentViewController:activityVC animated:YES completion:nil];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.logs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:11];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.backgroundColor = [UIColor blackColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    NSString *log = self.logs[indexPath.row];
    cell.textLabel.text = log;
    
    if ([log containsString:@"[MQTT SOURCE]"] && [log containsString:@"FOUND"]) {
        cell.textLabel.textColor = [UIColor systemGreenColor];
    } else if ([log containsString:@"[MQTT HTTP]"]) {
        cell.textLabel.textColor = [UIColor systemBlueColor];
    } else if ([log containsString:@"[MQTT TOKEN]"]) {
        cell.textLabel.textColor = [UIColor systemYellowColor];
    } else if ([log containsString:@"[MQTT DEFAULTS]"]) {
        cell.textLabel.textColor = [UIColor systemOrangeColor];
    } else if ([log containsString:@"[MQTT KVC]"]) {
        cell.textLabel.textColor = [UIColor systemPurpleColor];
    }
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

@end

@interface MqttFloatingButton : UIView
@property (nonatomic, strong) UIView *capsule;
@property (nonatomic, strong) UILabel *statusLabel;
+ (instancetype)shared;
- (void)installIfNeeded;
- (void)updateStatus:(NSString *)status;
@end

@implementation MqttFloatingButton

static MqttFloatingButton *_shared = nil;

+ (instancetype)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [MqttFloatingButton new];
    });
    return _shared;
}

- (UIWindow *)activeWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ws.windows) if (w.isKeyWindow) return w;
        if (ws.windows.count) return ws.windows.firstObject;
    }
    return nil;
}

- (void)installIfNeeded {
    if (self.capsule) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self activeWindow];
        if (!window) return;
        
        CGFloat screenW = window.bounds.size.width;
        CGFloat capsuleW = 120;
        CGFloat capsuleH = 36;
        
        CGFloat capsuleY = 52;
        CGFloat capsuleX = screenW - capsuleW - 12;
        
        UIView *c = [[UIView alloc] initWithFrame:CGRectMake(capsuleX, capsuleY, capsuleW, capsuleH)];
        c.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        c.layer.cornerRadius = capsuleH / 2;
        c.layer.masksToBounds = YES;
        c.layer.borderWidth = 1;
        c.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.6].CGColor;
        
        UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, 20, capsuleH)];
        icon.text = @"🔍";
        icon.font = [UIFont systemFontOfSize:14];
        [c addSubview:icon];
        
        _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(28, 0, capsuleW - 36, capsuleH)];
        _statusLabel.text = @"搜索中";
        _statusLabel.textColor = [UIColor whiteColor];
        _statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [c addSubview:_statusLabel];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openLog)];
        [c addGestureRecognizer:tap];
        
        [window addSubview:c];
        self.capsule = c;
    });
}

- (void)updateStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLabel.text = status;
    });
}

- (void)openLog {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self activeWindow];
        UIViewController *root = window.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        
        MqttLogViewController *vc = [[MqttLogViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.navigationBar.barStyle = UIBarStyleBlack;
        nav.navigationBar.tintColor = [UIColor whiteColor];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [root presentViewController:nav animated:YES completion:nil];
    });
}

@end

static NSString *kKnownUsername = @"d4a107b765f38550d13a24b54fdcdecf";
static NSString *kKnownPassword = @"7c039ddfbdad50f3d0caf974fbcd5a5f";
static NSString *kKnownClientId = @"LK6ADAH92RB765125_4456";

static BOOL isMqttCredential(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    return [value isEqualToString:kKnownUsername] || 
           [value isEqualToString:kKnownPassword] ||
           [value isEqualToString:kKnownClientId];
}

static void logFound(NSString *source, NSString *key, id value) {
    NSString *msg = [NSString stringWithFormat:@"[MQTT SOURCE] ✅ FOUND in %@: key=%@ value=%@", source, key, value];
    [[MqttLogManager sharedInstance] addLog:msg];
    [[MqttFloatingButton shared] updateStatus:@"找到来源!"];
}

%hook NSUserDefaults

- (id)objectForKey:(NSString *)defaultName {
    id result = %orig;
    
    if (result && [result isKindOfClass:[NSString class]] && isMqttCredential(result)) {
        logFound(@"NSUserDefaults objectForKey:", defaultName, result);
        
        NSArray *callStack = [NSThread callStackSymbols];
        for (NSString *symbol in callStack) {
            if ([symbol containsString:@"LingLingBang"]) {
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT DEFAULTS]   %@", symbol]];
            }
        }
    }
    
    return result;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    if (value && [value isKindOfClass:[NSString class]] && isMqttCredential(value)) {
        logFound(@"NSUserDefaults setObject:forKey:", defaultName, value);
        
        NSArray *callStack = [NSThread callStackSymbols];
        for (NSString *symbol in callStack) {
            if ([symbol containsString:@"LingLingBang"]) {
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT DEFAULTS]   %@", symbol]];
            }
        }
    }
    
    %orig;
}

%end

%hook NSObject

- (void)setValue:(id)value forKey:(NSString *)key {
    if (value && [value isKindOfClass:[NSString class]] && isMqttCredential(value)) {
        logFound(@"NSObject setValue:forKey:", key, value);
        
        [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KVC]   object class: %@", [self class]]];
        
        NSArray *callStack = [NSThread callStackSymbols];
        for (NSString *symbol in callStack) {
            if ([symbol containsString:@"LingLingBang"]) {
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KVC]   %@", symbol]];
            }
        }
    }
    
    %orig;
}

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request 
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    
    NSString *url = request.URL.absoluteString;
    
    if ([url containsString:@"botai"] || 
        [url containsString:@"mqtt"] ||
        [url containsString:@"token"] ||
        [url containsString:@"openapi.baojun"]) {
        
        [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HTTP] >>> %@ %@", request.HTTPMethod, url]];
        
        if (request.HTTPBody) {
            NSString *body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            if (body) {
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HTTP]   Body: %@", body]];
            }
        }
        
        void(^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data) {
                NSString *responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (responseStr) {
                    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HTTP] <<< Response: %@", responseStr]];
                    
                    if ([responseStr containsString:kKnownUsername] || 
                        [responseStr containsString:kKnownPassword]) {
                        [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT SOURCE] ✅ FOUND in HTTP Response! URL: %@", url]];
                    }
                }
            }
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };
        
        return %orig(request, wrappedHandler);
    }
    
    return %orig(request, completionHandler);
}

%end

%hook CYUnifiedMQTTHelper

- (void)loginMQTT {
    [[MqttLogManager sharedInstance] addLog:@"[MQTT SOURCE] >>> loginMQTT 被调用"];
    [[MqttFloatingButton shared] updateStatus:@"登录中..."];
    %orig;
}

- (void)connectWithUsername:(NSString *)username 
                   password:(NSString *)password 
                   clientId:(NSString *)clientId 
                    success:(id)success 
                    failure:(id)failure {
    
    [[MqttLogManager sharedInstance] addLog:@"[MQTT SOURCE] ============================"];
    [[MqttLogManager sharedInstance] addLog:@"[MQTT SOURCE] connectWithUsername:"];
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT SOURCE]   Username: %@", username]];
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT SOURCE]   Password: %@", password]];
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT SOURCE]   ClientID: %@", clientId]];
    [[MqttLogManager sharedInstance] addLog:@"[MQTT SOURCE] ============================"];
    
    NSArray *callStack = [NSThread callStackSymbols];
    [[MqttLogManager sharedInstance] addLog:@"[MQTT SOURCE] 完整堆栈:"];
    for (NSString *symbol in callStack) {
        [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT SOURCE]   %@", symbol]];
    }
    
    [[MqttFloatingButton shared] updateStatus:@"已连接!"];
    
    %orig;
}

%end

// ============================================
// MARK: - Hook Keychain (SecItem)
// ============================================

extern OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result);
extern OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result);

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);
static OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result);

static NSString *kKnownUsername = @"d4a107b765f38550d13a24b54fdcdecf";
static NSString *kKnownPassword = @"7c039ddfbdad50f3d0caf974fbcd5a5f";

static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus status = orig_SecItemCopyMatching(query, result);
    
    if (status == errSecSuccess && result && *result) {
        NSDictionary *queryDict = (__bridge NSDictionary *)query;
        NSString *service = queryDict[(__bridge id)kSecAttrService];
        NSString *account = queryDict[(__bridge id)kSecAttrAccount];
        
        // 检查返回的数据
        if (CFGetTypeID(*result) == CFDataGetTypeID()) {
            NSData *data = (__bridge NSData *)*result;
            NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            if (value && ([value isEqualToString:kKnownUsername] || [value isEqualToString:kKnownPassword])) {
                [[MqttLogManager sharedInstance] addLog:@"[MQTT KEYCHAIN] ✅ 读取到 MQTT 凭据!"];
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KEYCHAIN]   Service: %@", service]];
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KEYCHAIN]   Account: %@", account]];
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KEYCHAIN]   Value: %@", value]];
                
                NSArray *callStack = [NSThread callStackSymbols];
                [[MqttLogManager sharedInstance] addLog:@"[MQTT KEYCHAIN] 堆栈:"];
                for (NSString *symbol in callStack) {
                    if ([symbol containsString:@"LingLingBang"]) {
                        [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KEYCHAIN]   %@", symbol]];
                    }
                }
            }
        }
    }
    
    return status;
}

static OSStatus hook_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSDictionary *attrDict = (__bridge NSDictionary *)attributes;
    NSString *service = attrDict[(__bridge id)kSecAttrService];
    NSString *account = attrDict[(__bridge id)kSecAttrAccount];
    NSData *data = attrDict[(__bridge id)kSecValueData];
    
    if (data) {
        NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        if (value && ([value isEqualToString:kKnownUsername] || [value isEqualToString:kKnownPassword])) {
            [[MqttLogManager sharedInstance] addLog:@"[MQTT KEYCHAIN] ✅ 写入 MQTT 凭据!"];
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KEYCHAIN]   Service: %@", service]];
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KEYCHAIN]   Account: %@", account]];
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KEYCHAIN]   Value: %@", value]];
            
            NSArray *callStack = [NSThread callStackSymbols];
            [[MqttLogManager sharedInstance] addLog:@"[MQTT KEYCHAIN] 堆栈:"];
            for (NSString *symbol in callStack) {
                if ([symbol containsString:@"LingLingBang"]) {
                    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT KEYCHAIN]   %@", symbol]];
                }
            }
        }
    }
    
    return orig_SecItemAdd(attributes, result);
}

%ctor {
    %init;
    
    // Hook Keychain 函数
    MSHookFunction(SecItemCopyMatching, hook_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching);
    MSHookFunction(SecItemAdd, hook_SecItemAdd, (void **)&orig_SecItemAdd);
    
    NSLog(@"[MQTT SOURCE GRABBER] 🔍 Tweak 已加载！");
    [[MqttLogManager sharedInstance] addLog:@"[MQTT SOURCE] 🔍 Tweak 已加载，开始搜索凭据来源..."];
    [[MqttLogManager sharedInstance] addLog:@"[MQTT SOURCE] 已 Hook Keychain (SecItem)"];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[MqttFloatingButton shared] installIfNeeded];
    });
}
