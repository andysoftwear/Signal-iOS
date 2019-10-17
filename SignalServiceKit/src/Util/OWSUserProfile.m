//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSUserProfile.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_LocalProfileDidChange = @"kNSNotificationName_LocalProfileDidChange";
NSString *const kNSNotificationName_OtherUsersProfileWillChange = @"kNSNotificationName_OtherUsersProfileWillChange";
NSString *const kNSNotificationName_OtherUsersProfileDidChange = @"kNSNotificationName_OtherUsersProfileDidChange";

NSString *const kNSNotificationKey_ProfileAddress = @"kNSNotificationKey_ProfileAddress";
NSString *const kNSNotificationKey_ProfileGroupId = @"kNSNotificationKey_ProfileGroupId";

NSString *const kLocalProfileUniqueId = @"kLocalProfileUniqueId";

NSUInteger const kUserProfileSchemaVersion = 1;

@interface OWSUserProfile ()

@property (atomic, nullable) OWSAES256Key *profileKey;
@property (atomic, nullable) NSString *profileName;
@property (atomic, nullable) NSString *username;
@property (atomic, nullable) NSString *avatarUrlPath;
@property (atomic, nullable) NSString *avatarFileName;

@property (atomic, readonly) NSUInteger userProfileSchemaVersion;
@property (atomic, nullable, readonly) NSString *recipientPhoneNumber;
@property (atomic, nullable, readonly) NSString *recipientUUID;

@end

#pragma mark -

@implementation OWSUserProfile

@synthesize avatarUrlPath = _avatarUrlPath;
@synthesize avatarFileName = _avatarFileName;
@synthesize profileName = _profileName;


- (id<StorageServiceManagerProtocol>)storageServiceManager
{
    return SSKEnvironment.shared.storageServiceManager;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                  avatarFileName:(nullable NSString *)avatarFileName
                   avatarUrlPath:(nullable NSString *)avatarUrlPath
                      profileKey:(nullable OWSAES256Key *)profileKey
                     profileName:(nullable NSString *)profileName
            recipientPhoneNumber:(nullable NSString *)recipientPhoneNumber
                   recipientUUID:(nullable NSString *)recipientUUID
                        username:(nullable NSString *)username
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _avatarFileName = avatarFileName;
    _avatarUrlPath = avatarUrlPath;
    _profileKey = profileKey;
    _profileName = profileName;
    _recipientPhoneNumber = recipientPhoneNumber;
    _recipientUUID = recipientUUID;
    _username = username;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

+ (NSString *)collection
{
    // Legacy class name.
    return @"UserProfile";
}

+ (AnyUserProfileFinder *)userProfileFinder
{
    return [AnyUserProfileFinder new];
}

+ (SignalServiceAddress *)localProfileAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:kLocalProfileUniqueId];
}

+ (nullable OWSUserProfile *)getUserProfileForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    return [self.userProfileFinder userProfileForAddress:address transaction:transaction];
}

+ (OWSUserProfile *)getOrBuildUserProfileForAddress:(SignalServiceAddress *)address
                                        transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile =
        [self.userProfileFinder userProfileForAddress:address transaction:transaction];

    if (!userProfile) {
        userProfile = [[OWSUserProfile alloc] initWithAddress:address];

        if ([address.phoneNumber isEqualToString:kLocalProfileUniqueId]) {
            [userProfile updateWithProfileKey:[OWSAES256Key generateRandomKey] transaction:transaction completion:nil];
        }
    }

    OWSAssertDebug(userProfile);

    return userProfile;
}

+ (nullable OWSUserProfile *)userProfileForUsername:(NSString *)username
                                        transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(username.length > 0);

    return [self.userProfileFinder userProfileForUsername:username transaction:transaction];
}

+ (BOOL)localUserProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.userProfileFinder userProfileForAddress:self.localProfileAddress transaction:transaction] != nil;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super initWithCoder:coder]) {
        if (_userProfileSchemaVersion < 1) {
            _recipientPhoneNumber = [coder decodeObjectForKey:@"recipientId"];
            OWSAssertDebug(_recipientPhoneNumber);
        }

        _userProfileSchemaVersion = kUserProfileSchemaVersion;
    }

    return self;
}

- (instancetype)initWithAddress:(SignalServiceAddress *)address
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(address.isValid);
    _recipientPhoneNumber = address.phoneNumber;
    _recipientUUID = address.uuidString;
    _userProfileSchemaVersion = kUserProfileSchemaVersion;

    return self;
}

#pragma mark - Dependencies

- (id<OWSSyncManagerProtocol>)syncManager
{
    return SSKEnvironment.shared.syncManager;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

- (SignalServiceAddress *)address
{
    return [[SignalServiceAddress alloc] initWithUuidString:self.recipientUUID phoneNumber:self.recipientPhoneNumber];
}

- (nullable NSString *)avatarUrlPath
{
    @synchronized(self) {
        return _avatarUrlPath;
    }
}

- (void)setAvatarUrlPath:(nullable NSString *)avatarUrlPath
{
    @synchronized(self) {
        if (_avatarUrlPath != nil && ![_avatarUrlPath isEqual:avatarUrlPath]) {
            // If the avatarURL was previously set and it changed, the old avatarFileName
            // can't still be valid. Clear it.
            // NOTE: `_avatarUrlPath` will momentarily be nil during initWithCoder -
            // which is why we verify it's non-nil before inadvertently "cleaning up" the
            // avatarFileName during initialization. If it were *actually* nil, as opposed
            // to just transiently nil during `initWithCoder` , there'd be no avatarFileName
            // to clean up anyway.
            self.avatarFileName = nil;
        }

        _avatarUrlPath = avatarUrlPath;
    }
}

- (nullable NSString *)avatarFileName
{
    @synchronized(self) {
        return _avatarFileName;
    }
}

- (void)setAvatarFileName:(nullable NSString *)avatarFileName
{
    @synchronized(self) {
        BOOL didChange = ![NSObject isNullableObject:_avatarFileName equalTo:avatarFileName];
        if (!didChange) {
            return;
        }

        if (_avatarFileName) {
            NSString *oldAvatarFilePath = [OWSUserProfile profileAvatarFilepathWithFilename:_avatarFileName];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [OWSFileSystem deleteFileIfExists:oldAvatarFilePath];
            });
        }

        _avatarFileName = avatarFileName;
    }
}

#pragma mark - Update With... Methods

// Similar in spirit to anyUpdateWithTransaction,
// but with significant differences.
//
// * We save if this entity is not in the database.
// * We skip redundant saves by diffing.
// * We kick off multi-device synchronization.
// * We fire "did change" notifications.
- (void)applyChanges:(void (^)(id))changeBlock
        functionName:(const char *)functionName
         transaction:(SDSAnyWriteTransaction *)transaction
          completion:(nullable OWSUserProfileCompletion)completion
{
    OWSAssertDebug(transaction);

    // This should be set to true if:
    //
    // * This profile has just been inserted.
    // * Updating the profile updated this instance.
    // * Updating the profile updated the "latest" instance.
    __block BOOL didChange = NO;

    OWSUserProfile *_Nullable latestInstance =
        [OWSUserProfile anyFetchWithUniqueId:self.uniqueId transaction:transaction];
    if (latestInstance != nil) {
        [self anyUpdateWithTransaction:transaction
                                 block:^(OWSUserProfile *profile) {
                                     // self might be the latest instance, so take a "before" snapshot
                                     // before any changes have been made.
                                     NSDictionary *beforeSnapshot = [profile.dictionaryValue copy];

                                     changeBlock(profile);

                                     NSDictionary *afterSnapshot = [profile.dictionaryValue copy];

                                     if (![beforeSnapshot isEqual:afterSnapshot]) {
                                         didChange = YES;
                                     }
                                 }];
    } else {
        changeBlock(self);
        [self anyInsertWithTransaction:transaction];
        didChange = YES;
    }

    if (completion) {
        [transaction addCompletionWithQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                                      block:completion];
    }

    if (!didChange) {
        return;
    }

    // Profile changes, record updates with storage service
    [self.storageServiceManager recordPendingUpdatesWithUpdatedAddresses:@[ self.address ]];

    BOOL isLocalUserProfile = [self.address.phoneNumber isEqualToString:kLocalProfileUniqueId];

    [transaction addCompletionWithQueue:dispatch_get_main_queue()
                                  block:^{
                                      if (isLocalUserProfile) {
                                          // We populate an initial (empty) profile on launch of a new install, but
                                          // until we have a registered account, syncing will fail (and there could not
                                          // be any linked device to sync to at this point anyway).
                                          if (self.tsAccountManager.isRegisteredPrimaryDevice
                                              && CurrentAppContext().isMainApp) {
                                              [[self.syncManager syncLocalContact] retainUntilComplete];
                                          }

                                          [[NSNotificationCenter defaultCenter]
                                              postNotificationNameAsync:kNSNotificationName_LocalProfileDidChange
                                                                 object:nil
                                                               userInfo:nil];
                                      } else {
                                          [[NSNotificationCenter defaultCenter]
                                              postNotificationNameAsync:kNSNotificationName_OtherUsersProfileWillChange
                                                                 object:nil
                                                               userInfo:@{
                                                                   kNSNotificationKey_ProfileAddress : self.address,
                                                               }];
                                          [[NSNotificationCenter defaultCenter]
                                              postNotificationNameAsync:kNSNotificationName_OtherUsersProfileDidChange
                                                                 object:nil
                                                               userInfo:@{
                                                                   kNSNotificationKey_ProfileAddress : self.address,
                                                               }];
                                      }
                                  }];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                avatarUrlPath:(nullable NSString *)avatarUrlPath
               avatarFileName:(nullable NSString *)avatarFileName
                  transaction:(SDSAnyWriteTransaction *)transaction
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [self
        applyChanges:^(OWSUserProfile *userProfile) {
            [userProfile setProfileName:[profileName ows_stripped]];
            // Always setAvatarUrlPath: before you setAvatarFileName: since
            // setAvatarUrlPath: may clear the avatar filename.
            [userProfile setAvatarUrlPath:avatarUrlPath];
            [userProfile setAvatarFileName:avatarFileName];
        }
        functionName:__PRETTY_FUNCTION__
         transaction:transaction
          completion:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                     username:(nullable NSString *)username
                avatarUrlPath:(nullable NSString *)avatarUrlPath
                  transaction:(SDSAnyWriteTransaction *)transaction
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [self
        applyChanges:^(OWSUserProfile *userProfile) {
            [userProfile setProfileName:[profileName ows_stripped]];
            [userProfile setUsername:username];
            [userProfile setAvatarUrlPath:avatarUrlPath];
        }
        functionName:__PRETTY_FUNCTION__
         transaction:transaction
          completion:completion];
}

- (void)updateWithAvatarUrlPath:(nullable NSString *)avatarUrlPath
                 avatarFileName:(nullable NSString *)avatarFileName
                    transaction:(SDSAnyWriteTransaction *)transaction
                     completion:(nullable OWSUserProfileCompletion)completion
{
    [self
        applyChanges:^(OWSUserProfile *userProfile) {
            // Always setAvatarUrlPath: before you setAvatarFileName: since
            // setAvatarUrlPath: may clear the avatar filename.
            [userProfile setAvatarUrlPath:avatarUrlPath];
            [userProfile setAvatarFileName:avatarFileName];
        }
        functionName:__PRETTY_FUNCTION__
         transaction:transaction
          completion:completion];
}

- (void)updateWithAvatarFileName:(nullable NSString *)avatarFileName
                     transaction:(SDSAnyWriteTransaction *)transaction
                      completion:(nullable OWSUserProfileCompletion)completion
{
    [self
        applyChanges:^(OWSUserProfile *userProfile) {
            [userProfile setAvatarFileName:avatarFileName];
        }
        functionName:__PRETTY_FUNCTION__
         transaction:transaction
          completion:completion];
}

- (void)clearWithProfileKey:(OWSAES256Key *)profileKey
                transaction:(SDSAnyWriteTransaction *)transaction
                 completion:(nullable OWSUserProfileCompletion)completion
{
    [self
        applyChanges:^(OWSUserProfile *userProfile) {
            [userProfile setProfileKey:profileKey];
            [userProfile setProfileName:nil];
            // Always setAvatarUrlPath: before you setAvatarFileName: since
            // setAvatarUrlPath: may clear the avatar filename.
            [userProfile setAvatarUrlPath:nil];
            [userProfile setAvatarFileName:nil];
        }
        functionName:__PRETTY_FUNCTION__
         transaction:transaction
          completion:completion];
}

- (void)updateWithProfileKey:(OWSAES256Key *)profileKey
                 transaction:(SDSAnyWriteTransaction *)transaction
                  completion:(nullable OWSUserProfileCompletion)completion
{
    OWSAssertDebug(profileKey);

    [self
        applyChanges:^(OWSUserProfile *userProfile) {
            [userProfile setProfileKey:profileKey];
        }
        functionName:__PRETTY_FUNCTION__
         transaction:transaction
          completion:completion];
}

- (void)updateWithProfileName:(nullable NSString *)profileName
                  transaction:(SDSAnyWriteTransaction *)transaction
                   completion:(nullable OWSUserProfileCompletion)completion
{
    [self
        applyChanges:^(OWSUserProfile *userProfile) {
            [userProfile setProfileName:profileName];
        }
        functionName:__PRETTY_FUNCTION__
         transaction:transaction
          completion:completion];
}

- (void)updateWithUsername:(nullable NSString *)username transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(username == nil || username.length > 0);

    [self
        applyChanges:^(OWSUserProfile *userProfile) {
            [userProfile setUsername:username];
        }
        functionName:__PRETTY_FUNCTION__
         transaction:transaction
          completion:nil];
}

// This should only be used in verbose, developer-only logs.
- (NSString *)debugDescription
{
    return [NSString stringWithFormat:@"%@ %p %@ %lu %@ %@ %@",
                     self.logTag,
                     self,
                     self.address,
                     (unsigned long)self.profileKey.keyData.length,
                     self.profileName,
                     self.avatarUrlPath,
                     self.avatarFileName];
}

- (nullable NSString *)profileName
{
    @synchronized(self) {
        return _profileName.filterStringForDisplay;
    }
}

- (void)setProfileName:(nullable NSString *)profileName
{
    @synchronized(self) {
        _profileName = profileName.filterStringForDisplay;
    }
}

#pragma mark - Profile Avatars Directory

+ (NSString *)profileAvatarFilepathWithFilename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

    return [self.profileAvatarsDirPath stringByAppendingPathComponent:filename];
}

+ (NSString *)legacyProfileAvatarsDirPath
{
    return [[OWSFileSystem appDocumentDirectoryPath] stringByAppendingPathComponent:@"ProfileAvatars"];
}

+ (NSString *)sharedDataProfileAvatarsDirPath
{
    return [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"ProfileAvatars"];
}

+ (nullable NSError *)migrateToSharedData
{
    OWSLogInfo(@"");

    return [OWSFileSystem moveAppFilePath:self.legacyProfileAvatarsDirPath
                       sharedDataFilePath:self.sharedDataProfileAvatarsDirPath];
}

+ (NSString *)profileAvatarsDirPath
{
    static NSString *profileAvatarsDirPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        profileAvatarsDirPath = self.sharedDataProfileAvatarsDirPath;

        [OWSFileSystem ensureDirectoryExists:profileAvatarsDirPath];
    });
    return profileAvatarsDirPath;
}

// TODO: We may want to clean up this directory in the "orphan cleanup" logic.

+ (void)resetProfileStorage
{
    OWSAssertIsOnMainThread();

    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self profileAvatarsDirPath] error:&error];
    if (error) {
        OWSLogError(@"Failed to delete database: %@", error.description);
    }
}

+ (NSSet<NSString *> *)allProfileAvatarFilePathsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSString *profileAvatarsDirPath = self.profileAvatarsDirPath;
    NSMutableSet<NSString *> *profileAvatarFilePaths = [NSMutableSet new];
    [OWSUserProfile anyEnumerateWithTransaction:transaction
                                        batched:YES
                                          block:^(OWSUserProfile *userProfile, BOOL *stop) {
                                              if (!userProfile.avatarFileName) {
                                                  return;
                                              }
                                              NSString *filePath = [profileAvatarsDirPath
                                                  stringByAppendingPathComponent:userProfile.avatarFileName];
                                              [profileAvatarFilePaths addObject:filePath];
                                          }];
    return [profileAvatarFilePaths copy];
}

@end

NS_ASSUME_NONNULL_END
