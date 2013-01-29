/* vim: set ft=objc fenc=utf-8 sw=2 ts=2 et: */

#import "User.h"

@implementation User

@dynamic userID;
@dynamic name;
@dynamic followers;
@dynamic following;

- (id)init
{
  self = [super init];
  if (self) {
    [self setFollowers:[NSMutableArray array]];
    [self setFollowing:[NSMutableArray array]];
  }

  return self;
}

- (NSArray *)friends
{
  NSMutableSet *set = [[self followers] mutableCopy];
  [set intersectSet:[self following]];
  return [set allObjects];
}

- (BOOL)isFollowedBy:(User *)user
{
  return [[self followers] containsObject:[user userID]];
}

- (BOOL)isFollowing:(User *)user
{
  return [[self following] containsObject:[user userID]];
}

- (void)follow:(User *)user
{
  if ([self isEqual:user]) {
    return;
  }

  [self willChangeValueForKey:@"following"];
  [user willChangeValueForKey:@"followers"];
  [[self following] addObject:[user userID]];
  [[user followers] addObject:[self userID]];
  [self didChangeValueForKey:@"following"];
  [user didChangeValueForKey:@"followers"];
}

- (void)unfollow:(User *)user
{
  if ([self isEqual:user]) {
    return;
  }

  [self willChangeValueForKey:@"following"];
  [user willChangeValueForKey:@"followers"];
  [[self following] removeObject:[user userID]];
  [[user followers] removeObject:[self userID]];
  [self didChangeValueForKey:@"following"];
  [user didChangeValueForKey:@"followers"];
}

@end
