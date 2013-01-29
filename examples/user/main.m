/* vim: set ft=objc fenc=utf-8 sw=2 ts=2 et: */

#import <Foundation/Foundation.h>
#import "VSDataStore.h"
#import "User.h"

int main(int argc, const char * argv[])
{
  @autoreleasepool {
    VSDataStoreInitializationHint();

    if ([[[VSDataManager defaultManager] dataObjectsForClass:[User class]] count] > 0) {
      for (User *user in [[VSDataManager defaultManager] dataObjectsForClass:[User class]]) {
        NSLog(@"%@", user);
      }
    }
    else {
      User *user1 = [[User alloc] init];
      [user1 setUserID:@"user1"];
      [user1 setName:@"User One"];
      [[VSDataManager defaultManager] addDataObject:user1];

      User *user2 = [[User alloc] init];
      [user2 setUserID:@"user2"];
      [user2 setName:@"User Two"];
      [[VSDataManager defaultManager] addDataObject:user2];

      [user2 follow:user1];

      [[VSDataManager defaultManager] sync];
    }
  }

  return 0;
}

