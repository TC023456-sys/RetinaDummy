#import <Foundation/Foundation.h>

static inline BOOL RetinaAutomaticUpdateDue(BOOL enabled, NSTimeInterval last, NSTimeInterval attempted, NSTimeInterval now) {
    return enabled && now - last >= 86400 && now - attempted >= 3600;
}

// Only stable Retina Dummy releases with the exact asset in this repository qualify.
static inline NSDictionary *RetinaLatestRelease(NSArray *releases) {
    if (![releases isKindOfClass:NSArray.class]) return nil;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^v[0-9]+\\.[0-9]+\\.[0-9]+$" options:0 error:nil];
    NSDictionary *latest = nil;
    for (id value in releases) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *release = value;
        if (![release[@"draft"] isKindOfClass:NSNumber.class] || ![release[@"prerelease"] isKindOfClass:NSNumber.class] ||
            [release[@"draft"] boolValue] || [release[@"prerelease"] boolValue]) continue;
        NSString *tag = release[@"tag_name"];
        if (![tag isKindOfClass:NSString.class] || ![pattern firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)]) continue;
        NSString *page = [@"https://github.com/TC023456-sys/RetinaDummy/releases/tag/" stringByAppendingString:tag];
        if (![release[@"html_url"] isEqual:page]) continue;
        NSString *expected = [NSString stringWithFormat:@"https://github.com/TC023456-sys/RetinaDummy/releases/download/%@/Retina-Dummy.zip", tag];
        NSArray *assets = release[@"assets"];
        if (![assets isKindOfClass:NSArray.class]) continue;
        for (id asset in assets) {
            if (![asset isKindOfClass:NSDictionary.class] || ![asset[@"name"] isEqual:@"Retina-Dummy.zip"] || ![asset[@"browser_download_url"] isEqual:expected]) continue;
            NSString *version = [tag substringFromIndex:1];
            if (!latest || [version compare:latest[@"version"] options:NSNumericSearch] == NSOrderedDescending) {
                latest = @{@"version":version, @"download":expected};
            }
        }
    }
    return latest;
}
