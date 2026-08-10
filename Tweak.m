// NBA 2K20 iOS Mod Menu - 海鸥出品
// 原理: 直接写 __bss 段能力值数组 + 后台线程每50ms刷新
// 不需要 hook, 不需要越狱, TrollStore 直接注入
//
// 已逆向确认的内存布局 (主程序 vmaddr):
//   能力数组结构基址   0x10227A2C8  (struct { count@+4, data@+8 })
//   玩家能力索引指针   0x10270C034  (int, 当前玩家 slot)
//   比赛时间 float     0x102703060
//   进攻时间 float     0x102703090
//   能力值 = data + slot*4 + 偏移 (float)
//
// 能力偏移表 (每项 float, 间隔 0x8):
//   +0x04 抢断  +0x0c 盖帽  +0x14 速度  +0x1c 控球
//   +0x24 灌篮  +0x2c 进攻意识 +0x34 防守意识 +0x3c 进攻篮板
//   +0x44 防守篮板 +0x4c 力量 +0x54 敏捷 +0x5c 活跃
//   +0x64 稳定性 +0x6c 耐久 +0x74 体力 +0x7c 手感
//   +0x84 弹跳  +0x8c 持球防守

#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <pthread.h>
#import <dlfcn.h>

// ========== 逆向出的地址 (主程序 vmaddr) ==========
#define TEXT_BASE            0x100000000ULL
#define ABILITY_STRUCT       0x10227A2C8ULL   // struct{ count@+4, data@+8 }
#define PLAYER_SLOT_PTR      0x10270C034ULL   // int* 当前玩家 slot 索引
#define GAME_CLOCK_ADDR      0x102703060ULL   // float 比赛时间
#define SHOT_CLOCK_ADDR      0x102703090ULL   // float 进攻时间

// ========== 能力偏移表 ==========
typedef struct { const char *name; uint32_t off; } AbilityDef;

static const AbilityDef kAbilities[] = {
    { "抢断",       0x04 },
    { "盖帽",       0x0c },
    { "速度",       0x14 },
    { "控球",       0x1c },
    { "灌篮",       0x24 },
    { "进攻意识",   0x2c },
    { "防守意识",   0x34 },
    { "进攻篮板",   0x3c },
    { "防守篮板",   0x44 },
    { "力量",       0x4c },
    { "敏捷",       0x54 },
    { "活跃",       0x5c },
    { "稳定性",     0x64 },
    { "耐久",       0x6c },
    { "体力",       0x74 },
    { "手感",       0x7c },
    { "弹跳",       0x84 },
    { "持球防守",   0x8c },
};
#define ABILITY_COUNT (sizeof(kAbilities)/sizeof(kAbilities[0]))

// ========== mod 状态 (线程安全, 用原子) ==========
static volatile bool g_maxAll       = false;  // 全属性99
static volatile float g_allValue    = 99.0f;
static volatile bool g_freezeClock  = false;  // 锁比赛时间 12分钟制11:00
static volatile bool g_freezeShot   = false;  // 锁进攻时间 24秒
static volatile bool g_bulletMode   = false;  // 超级速度(比赛时间冻结在剩余值)

// ========== 运行时地址计算 ==========
static uintptr_t g_slide = 0;

static inline void *ADDR(uintptr_t vmaddr) {
    return (void *)(vmaddr + g_slide);
}

static bool g_ready = false;

// 检查结构是否就绪: [struct+4] 为有效count
static bool abilitiesReady(void) {
    volatile uint32_t *count = (volatile uint32_t *)ADDR(ABILITY_STRUCT + 4);
    return count && *count > 0 && *count < 0x100;
}

// 当前玩家 slot 索引
static int currentSlot(void) {
    volatile int32_t *slot = (volatile int32_t *)ADDR(PLAYER_SLOT_PTR);
    if (!slot) return 0;
    int s = *slot;
    return (s >= 0 && s < 64) ? s : 0;
}

// 能力数组数据区地址
static volatile float *abilityDataPtr(void) {
    return (volatile float *)ADDR(ABILITY_STRUCT + 8);
}

// ========== 写入函数 ==========
static void writeAbility(const AbilityDef *a, float v) {
    volatile float *data = abilityDataPtr();
    if (!data) return;
    int slot = currentSlot();
    volatile float *p = data + slot + (a->off / 4);
    *p = v;
}

// 后台刷新线程: 每50ms把所有启用项写一遍
static void *writerLoop(void *unused) {
    (void)unused;
    while (1) {
        usleep(50000); // 50ms

        if (g_maxAll) {
            if (abilitiesReady()) {
                for (int i = 0; i < ABILITY_COUNT; i++) {
                    writeAbility(&kAbilities[i], g_allValue);
                }
            }
        }
        if (g_freezeClock) {
            volatile float *c = (volatile float *)ADDR(GAME_CLOCK_ADDR);
            if (c) *c = 660.0f; // 11:00
        }
        if (g_freezeShot) {
            volatile float *c = (volatile float *)ADDR(SHOT_CLOCK_ADDR);
            if (c) *c = 24.0f;
        }
    }
    return NULL;
}

// ========== 浮层菜单 UI ==========
@interface ModMenuView : UIView
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, assign) BOOL menuOpen;
@end

@interface ModRootVC : UIViewController
@property (nonatomic, strong) ModMenuView *menuView;
@end

@implementation ModRootVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.menuView = [[ModMenuView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.menuView];
}
@end

static UIWindow *g_menuWindow = nil;

@implementation ModMenuView {
    UISwitch *swMax;
    UISlider *slAll;
    UISwitch *swClock;
    UISwitch *swShot;
    UILabel *lblAll;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = YES;
        self.menuOpen = NO;

        // 悬浮按钮
        self.toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        self.toggleBtn.frame = CGRectMake(12, 60, 48, 48);
        [self.toggleBtn setTitle:@"🐦" forState:UIControlStateNormal];
        self.toggleBtn.titleLabel.font = [UIFont systemFontOfSize:28];
        self.toggleBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        self.toggleBtn.layer.cornerRadius = 24;
        self.toggleBtn.clipsToBounds = YES;
        [self.toggleBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.toggleBtn];

        // 面板
        UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(12, 120, 220, 0)];
        panel.tag = 99;
        panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
        panel.layer.cornerRadius = 10;
        panel.clipsToBounds = YES;
        [self addSubview:panel];

        CGFloat y = 10;
        CGFloat h = 34;

        // 全属性拉满
        UILabel *lbMax = [self label:@"全属性拉满" y:y];
        [panel addSubview:lbMax];
        swMax = [self aSwitch];
        swMax.center = CGPointMake(190, y + h/2);
        [swMax addTarget:self action:@selector(chgMax) forControlEvents:UIControlEventValueChanged];
        [panel addSubview:swMax];
        y += h;

        // 属性值滑块
        slAll = [[UISlider alloc] initWithFrame:CGRectMake(10, y, 200, 28)];
        slAll.minimumValue = 50;
        slAll.maximumValue = 99;
        slAll.value = 99;
        [slAll addTarget:self action:@selector(chgSlider) forControlEvents:UIControlEventValueChanged];
        [panel addSubview:slAll];
        lblAll = [self label:@"99" y:y+4];
        lblAll.frame = CGRectMake(150, y+4, 60, 20);
        lblAll.textAlignment = NSTextAlignmentRight;
        [panel addSubview:lblAll];
        y += 36;

        // 锁比赛时间
        UILabel *lbClock = [self label:@"锁比赛时间(11:00)" y:y];
        [panel addSubview:lbClock];
        swClock = [self aSwitch];
        swClock.center = CGPointMake(190, y + h/2);
        [swClock addTarget:self action:@selector(chgClock) forControlEvents:UIControlEventValueChanged];
        [panel addSubview:swClock];
        y += h;

        // 锁进攻时间
        UILabel *lbShot = [self label:@"锁进攻时间(24秒)" y:y];
        [panel addSubview:lbShot];
        swShot = [self aSwitch];
        swShot.center = CGPointMake(190, y + h/2);
        [swShot addTarget:self action:@selector(chgShot) forControlEvents:UIControlEventValueChanged];
        [panel addSubview:swShot];
        y += h + 10;

        panel.frame = CGRectMake(12, 120, 220, y);
        panel.hidden = YES;
    }
    return self;
}

- (UILabel *)label:(NSString *)txt y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12, y, 160, 34)];
    l.text = txt;
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = [UIColor whiteColor];
    return l;
}

- (UISwitch *)aSwitch {
    UISwitch *s = [[UISwitch alloc] init];
    s.onTintColor = [UIColor systemBlueColor];
    return s;
}

- (void)toggleMenu {
    UIView *panel = [self viewWithTag:99];
    self.menuOpen = !self.menuOpen;
    panel.hidden = !self.menuOpen;
}

- (void)chgMax   { g_maxAll = swMax.on; }
- (void)chgClock { g_freezeClock = swClock.on; }
- (void)chgShot  { g_freezeShot = swShot.on; }
- (void)chgSlider {
    g_allValue = slAll.value;
    lblAll.text = [NSString stringWithFormat:@"%d", (int)slAll.value];
    if (swMax.on) g_maxAll = true; // 拉满数值跟随滑块
}
@end

// ========== 入口: dylib 加载时执行 ==========
__attribute__((constructor))
static void initMod(void) {
    // 获取主程序 ASLR slide
    const struct mach_header *hdr = _dyld_get_image_header(0);
    if (!hdr) return;
    g_slide = _dyld_get_image_vmaddr_slide(0);

    // 启动写入线程
    pthread_t t;
    pthread_create(&t, NULL, writerLoop, NULL);

    // 延迟创建 UI (等游戏 UIApplication 起来)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @autoreleasepool {
            g_menuWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            g_menuWindow.windowLevel = UIWindowLevelStatusBar + 1;
            g_menuWindow.rootViewController = [[ModRootVC alloc] init];
            g_menuWindow.hidden = NO;
        }
    });
}
