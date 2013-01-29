/* vim: set ft=objc fenc=utf-8 sw=2 ts=2 et: */

#import <Foundation/Foundation.h>
#import "VSDataStore.h"

@interface User : VSDataObject

@property (nonatomic, strong) NSString *userID;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSMutableSet *followers;
@property (nonatomic, strong) NSMutableSet *following;

- (NSArray *)friends;

- (BOOL)isFollowedBy:(User *)user;
- (BOOL)isFollowing:(User *)user;

- (void)follow:(User *)user;
- (void)unfollow:(User *)user;

@end
