#import "../UpdateCheck.h"
static NSDictionary *Release(NSString *tag, NSString *asset, BOOL draft, BOOL prerelease, BOOL foreign) {
    NSString *repo = foreign ? @"other/repo" : @"TC023456-sys/RetinaDummy";
    return @{@"tag_name":tag, @"draft":@(draft), @"prerelease":@(prerelease),
             @"html_url":[NSString stringWithFormat:@"https://github.com/%@/releases/tag/%@", repo, tag],
             @"assets":@[@{@"name":asset, @"browser_download_url":[NSString stringWithFormat:@"https://github.com/%@/releases/download/%@/%@",repo,tag,asset]}]};
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray *items = @[Release(@"v0.8.2",@"Retina-Dummy.zip",NO,NO,NO), Release(@"v0.8.10",@"Retina-Dummy.zip",NO,NO,NO), Release(@"macshot-v99.0.0-finder.1",@"MacShot-Finder.zip",NO,NO,NO), Release(@"v99.0.0",@"Retina-Dummy.zip",YES,NO,NO), Release(@"v99.0.1",@"Retina-Dummy.zip",NO,YES,NO), Release(@"v99.0.2",@"Retina-Dummy.zip",NO,NO,YES)];
        NSCAssert([RetinaLatestRelease(items)[@"version"] isEqual:@"0.8.10"], @"numeric ordering and release filtering");
        NSCAssert(!RetinaLatestRelease(@[Release(@"v0.8.3", @"Other.zip", NO,NO,NO)]), @"asset required");
        NSCAssert(!RetinaLatestRelease(@[@{}, @"invalid"]), @"malformed input ignored");
        NSCAssert(!RetinaAutomaticUpdateDue(NO,0,0,100000), @"disabled stays quiet");
        NSCAssert(!RetinaAutomaticUpdateDue(YES,1000,0,87399), @"under 24h");
        NSCAssert(RetinaAutomaticUpdateDue(YES,1000,0,87400), @"24h boundary");
        NSCAssert(!RetinaAutomaticUpdateDue(YES,0,99000,100000), @"failed attempts throttled across restart");
        NSCAssert(RetinaAutomaticUpdateDue(YES,0,96400,100000), @"retry at 1h boundary");
        if (argc > 1) {
            NSData *data = [NSData dataWithContentsOfFile:@(argv[1])];
            NSDictionary *live = RetinaLatestRelease([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
            NSCAssert(live, @"live API must contain Retina release");
            printf("Live Retina version: %s\n", [live[@"version"] UTF8String]);
        }
        puts("PASS: Retina-only assets, numeric versions, stable-only filtering, repository validation and daily scheduling");
    }
}
