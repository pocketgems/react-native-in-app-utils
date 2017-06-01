#import "InAppUtils.h"
#import <StoreKit/StoreKit.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import "SKProduct+StringPrice.h"

@implementation InAppUtils
{
    NSArray *products;
    NSMutableDictionary *_callbacks;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _callbacks = [[NSMutableDictionary alloc] init];
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStateFailed: {
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    callback(@[RCTJSErrorFromNSError(transaction.error)]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state failed.");
                }
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStatePurchased: {
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    NSDictionary *purchase = @{
                                              @"transactionDate": @(transaction.transactionDate.timeIntervalSince1970 * 1000),
                                              @"transactionIdentifier": transaction.transactionIdentifier,
                                              @"productIdentifier": transaction.payment.productIdentifier,
                                              @"transactionReceipt": [[transaction transactionReceipt] base64EncodedStringWithOptions:0]
                                              };
                    callback(@[[NSNull null], purchase]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state purchased.");
                }
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStateRestored:
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"purchasing");
                break;
            case SKPaymentTransactionStateDeferred:
                NSLog(@"deferred");
                break;
            default:
                break;
        }
    }
}

RCT_EXPORT_METHOD(purchaseProduct:(NSString *)productIdentifier
                  callback:(RCTResponseSenderBlock)callback)
{
    SKProduct *product;
    for(SKProduct *p in products)
    {
        if([productIdentifier isEqualToString:p.productIdentifier]) {
            product = p;
            break;
        }
    }

    if(product) {
        SKPayment *payment = [SKPayment paymentWithProduct:product];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        _callbacks[RCTKeyForInstance(payment.productIdentifier)] = callback;
    } else {
        callback(@[@"invalid_product"]);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        callback(@[@"restore_failed"]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKPaymentTransaction *transaction in queue.transactions){
            if(transaction.transactionState == SKPaymentTransactionStateRestored) {

                NSMutableDictionary *purchase = [NSMutableDictionary dictionaryWithDictionary: @{
                    @"transactionDate": @(transaction.transactionDate.timeIntervalSince1970 * 1000),
                    @"transactionIdentifier": transaction.transactionIdentifier,
                    @"productIdentifier": transaction.payment.productIdentifier,
                    @"transactionReceipt": [[transaction transactionReceipt] base64EncodedStringWithOptions:0]
                }];

                SKPaymentTransaction *originalTransaction = transaction.originalTransaction;
                if (originalTransaction) {
                    purchase[@"originalTransactionDate"] = @(originalTransaction.transactionDate.timeIntervalSince1970 * 1000);
                    purchase[@"originalTransactionIdentifier"] = originalTransaction.transactionIdentifier;
                }

                [productsArrayForJS addObject:purchase];
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            }
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

RCT_EXPORT_METHOD(restorePurchases:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(loadProducts:(NSArray *)productIdentifiers
                  callback:(RCTResponseSenderBlock)callback)
{
    if([SKPaymentQueue canMakePayments]){
        SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                              initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
        productsRequest.delegate = self;
        _callbacks[RCTKeyForInstance(productsRequest)] = callback;
        [productsRequest start];
    } else {
        callback(@[@"not_available"]);
    }
}

RCT_EXPORT_METHOD(canMakePayments: (RCTResponseSenderBlock)callback)
{
    BOOL canMakePayments = [SKPaymentQueue canMakePayments];
    callback(@[@(canMakePayments)]);
}

RCT_EXPORT_METHOD(receiptData:(RCTResponseSenderBlock)callback)
{
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    if (!receiptData) {
      callback(@[@"not_available"]);
    } else {
      callback(@[[NSNull null], [receiptData base64EncodedStringWithOptions:0]]);
    }
}

// SKProductsRequestDelegate protocol method

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        // Ensure error.userData can be converted to JSON without error.
        // This will remove any NSURL from the error.userData.
        error = RCTErrorClean(error);
        callback(@[RCTJSErrorFromNSError(error)]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for request error.");
    }
}

static NSDictionary *subscriptionDetails(SKProduct *item) {
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
    numberFormatter.locale = item.priceLocale;
    
    NSDecimalNumber *price = item.price;
    NSString *priceString = item.priceString;
    
    NSDecimalNumber *weeksInAMonth = (NSDecimalNumber*)[NSDecimalNumber numberWithInt:4];
    NSDecimalNumber *monthsInAYear = (NSDecimalNumber*)[NSDecimalNumber numberWithInt:12];
    NSDecimalNumber *weeksInAYear = (NSDecimalNumber*)[NSDecimalNumber numberWithInt:52];
    
    BOOL gotDetails = NO;
    NSDecimalNumber *weeklyPrice, *monthlyPrice, *yearlyPrice;
    NSString *weeklyPriceString, *monthlyPriceString, *yearlyPriceString;
    
    if ([item.productIdentifier containsString:@"week"]) {
        gotDetails = YES;
        
        weeklyPrice = price;
        weeklyPriceString = priceString;
        
        monthlyPrice = [price decimalNumberByMultiplyingBy:weeksInAMonth];
        monthlyPriceString = [numberFormatter stringFromNumber:monthlyPrice];
        
        yearlyPrice = [price decimalNumberByMultiplyingBy:weeksInAYear];
        yearlyPriceString = [numberFormatter stringFromNumber:yearlyPrice];
    } else if ([item.productIdentifier containsString:@"month"]) {
        gotDetails = YES;
        
        weeklyPrice = [price decimalNumberByDividingBy:weeksInAMonth];
        weeklyPriceString = [numberFormatter stringFromNumber:weeklyPrice];
        
        monthlyPrice = price;
        monthlyPriceString = priceString;
        
        yearlyPrice = [price decimalNumberByMultiplyingBy:monthsInAYear];
        yearlyPriceString = [numberFormatter stringFromNumber:yearlyPrice];
    } else if ([item.productIdentifier containsString:@"year"]) {
        gotDetails = YES;
        
        weeklyPrice = [price decimalNumberByDividingBy:weeksInAYear];
        weeklyPriceString = [numberFormatter stringFromNumber:weeklyPrice];
        
        monthlyPrice = [price decimalNumberByDividingBy:monthsInAYear];
        monthlyPriceString = [numberFormatter stringFromNumber:monthlyPrice];
        
        yearlyPrice = price;
        yearlyPriceString = priceString;
    }
    
    if (gotDetails) {
        return @{
            @"weeklyPrice": weeklyPrice,
            @"weeklyPriceString": weeklyPriceString,
            @"monthlyPrice": monthlyPrice,
            @"monthlyPriceString": monthlyPriceString,
            @"yearlyPrice": yearlyPrice,
            @"yearlyPriceString": yearlyPriceString
        };
    }
    return nil;
}

static NSDictionary *mergeDictionaries(NSDictionary *a, NSDictionary *b) {
    NSMutableDictionary *merged = [[NSMutableDictionary alloc] initWithDictionary:a];
    [merged addEntriesFromDictionary:b];
    return merged;
}

- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        products = [NSMutableArray arrayWithArray:response.products];
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKProduct *item in response.products) {
            NSDictionary *product = @{
                                      @"identifier": item.productIdentifier,
                                      @"price": item.price,
                                      @"currencySymbol": [item.priceLocale objectForKey:NSLocaleCurrencySymbol],
                                      @"currencyCode": [item.priceLocale objectForKey:NSLocaleCurrencyCode],
                                      @"priceString": item.priceString,
                                      @"downloadable": item.downloadable ? @"true" : @"false" ,
                                      @"description": item.localizedDescription ? item.localizedDescription : @"",
                                      @"title": item.localizedTitle ? item.localizedTitle : @"",
                                      };
            
            NSDictionary *subscription = subscriptionDetails(item);
            if (subscription) {
                product = mergeDictionaries(product, subscription);
            }
            
            [productsArrayForJS addObject:product];
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for load product request.");
    }
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark Private

static NSString *RCTKeyForInstance(id instance)
{
    return [NSString stringWithFormat:@"%p", instance];
}

static NSError *RCTErrorClean(NSError *error) {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [RCTJSONClean(error.userInfo) enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && ![value isKindOfClass:NSNull.class]) {
            userInfo[key] = value;
        }
    }];
    
    return [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
}

@end
