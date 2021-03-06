//
//  EasyCenterManager.m
//  EasyBlueTooth
//
//  Created by nf on 2016/8/14.
//  Copyright © 2017年 chenSir. All rights reserved.
//

#import "EasyCenterManager.h"

#import "EasyService.h"
#import "EasyPeripheral.h"
#import "EasyDescriptor.h"
#import "EasyCharacteristic.h"

#import <UIKit/UIKit.h>


@interface EasyCenterManager()<CBCentralManagerDelegate>
{
    CBManagerState _centerState ;//当前系统蓝牙状态
    
    
    NSTimeInterval _scanTimeInterval ;      //当前扫描的时间
    NSArray *_scanServicesArray ;//扫描的条件
    NSDictionary *_scanOptionsDictionary ;//扫描条件
    blueToothSearchDeviceCallback _blueToothSearchDeviceCallback ;
    
    
    dispatch_source_t _searchDeviceTimer ;
}
@property (nonatomic, strong) NSMutableDictionary *foundDeviceDict;
@property (nonatomic, strong) NSMutableDictionary *connectedDeviceDict;

@end

@implementation EasyCenterManager

- (instancetype)initWithQueue:(dispatch_queue_t)queue
{
    if (self = [super init]) {
        _manager = [[CBCentralManager alloc]initWithDelegate:self queue:queue];
    }
    return self ;
}
- (instancetype)initWithQueue:(dispatch_queue_t)queue options:(NSDictionary *)options
{
    if (self = [super init]) {
        _manager = [[CBCentralManager alloc]initWithDelegate:self queue:queue options:options];
        _scanTimeInterval = LONG_MAX ;
    }
    return self ;
}
- (void)startScanDevice
{
    [self scanDeviceWithTimeInterval:_scanTimeInterval
                            callBack:_blueToothSearchDeviceCallback];
}
- (void)scanDeviceWithTimeCallback:(blueToothSearchDeviceCallback)searchDeviceCallBack
{
    [self scanDeviceWithTimeInterval:_scanTimeInterval
                            callBack:searchDeviceCallBack];
}
- (void)scanDeviceWithTimeInterval:(NSTimeInterval)timeInterval
                          callBack:(blueToothSearchDeviceCallback)searchDeviceCallBack
{
    [self scanDeviceWithTimeInterval:timeInterval
                            services:_scanServicesArray
                             options:_scanOptionsDictionary
                            callBack:searchDeviceCallBack];
}

- (void)scanDeviceWithTimeInterval:(NSTimeInterval)timeInterval
                          services:(NSArray *)service
                           options:(NSDictionary *)options
                          callBack:(blueToothSearchDeviceCallback)searchDeviceCallBack
{
    _scanTimeInterval = timeInterval ;
    _scanOptionsDictionary = options ;
    _scanServicesArray = service ;
    _blueToothSearchDeviceCallback = [searchDeviceCallBack copy] ;
    
    [self stopScanDevice];
    
    _isScanning = YES ;
    
    NSArray *connectedArray = [self retrieveConnectedPeripheralsWithServices:service];
    [connectedArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        //如果不在扫描设备、已连接设备的集合中就加入其中，并通知外部调用者
        EasyPeripheral *easyP = (EasyPeripheral *)obj ;
        BOOL isExited = NO ;
        for (NSUUID *tempIden in [self.foundDeviceDict allKeys]) {
            if ([tempIden isEqual:easyP.identifier]) {
                isExited = YES ;
                break  ;
            }
        }
        if (!isExited) {
            [self.foundDeviceDict setObject:easyP forKey:easyP.identifier];
        }
        
        if (_blueToothSearchDeviceCallback) {
            _blueToothSearchDeviceCallback(easyP ,!_isScanning);
        }
    }];
    
    
    [self.manager scanForPeripheralsWithServices:service options:options];

    //指定时间通知外部，扫描完成
    kWeakSelf(self)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        _isScanning = NO ;
        
        if (weakself.manager.isScanning && _blueToothSearchDeviceCallback) {
            _blueToothSearchDeviceCallback(nil,!_isScanning);
            [weakself.manager stopScan];
        }
        
    });
}

- (void)stopScanDevice
{
 
    if (_isScanning) {
        _isScanning = NO ;
    }
    [self.manager stopScan];
    
}

- (void)removeAllScanFoundDevice
{
    [self.foundDeviceDict removeAllObjects];
}

- (void)disConnectAllDevice
{
    for (EasyPeripheral *tempPeripheral in [self.connectedDeviceDict allValues]) {
        [tempPeripheral disconnectDevice];
    }
}

- (EasyPeripheral *)searchDeviceWithPeripheral:(CBPeripheral *)peripheral
{
    EasyPeripheral *result = nil;
    NSArray *tempArray = [NSArray arrayWithArray:[self.connectedDeviceDict allValues]];
    for (EasyPeripheral *tempPeripheral in tempArray) {
        if ([tempPeripheral.peripheral isEqual: peripheral]) {
            result = tempPeripheral;
            break;
        }
    }
    return result;
}


#pragma mark - centeral manager delegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    EasyLog(@"\n蓝牙状态发生改变：%@ - %zd",central , central.state);
    //状态改变，清除所有连接 和发现的设别
    if (_centerState != central.state) {
        [self disConnectAllDevice];
        [self removeAllScanFoundDevice];
        
        if (_stateChangeCallback) {
            _stateChangeCallback(self , central.state );
        }
    }
    _centerState = central.state ;
    
    if (_centerState == CBManagerStateUnsupported) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"此设备不支持BLE4.0,请更换设备" preferredStyle:UIAlertControllerStyleAlert];
        [UIApplication sharedApplication].keyWindow.rootViewController = alert ;
    }
    
    switch (central.state) {
        case CBCentralManagerStatePoweredOn:
            //            [self startScanDevice];
            break ;
        case CBCentralManagerStatePoweredOff:
            break ;
        default:
            break ;
    }
    
}

- (void)centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary<NSString *, id> *)dict
{
    EasyLog(@"\n蓝牙状态即将重置：%@ - %zd",central , dict);

    //dict中会传入如下键值对
    /*
     3 //恢复连接的外设数组
     4 NSString *const CBCentralManagerRestoredStatePeripheralsKey;
     5 //恢复连接的服务UUID数组
     6 NSString *const CBCentralManagerRestoredStateScanServicesKey;
     7 //恢复连接的外设扫描属性字典数组
     8 NSString *const CBCentralManagerRestoredStateScanOptionsKey;
     9 */
}


- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    EasyLog(@"%@\n", [NSString stringWithFormat:@"发现一个设备 - %@ - %@" ,peripheral.name,RSSI] );
    
    //去掉重复搜索到的设备
    NSInteger existedIndex = -1 ;
    for (NSUUID *tempIndefy in [self.foundDeviceDict allKeys]) {
        if ([tempIndefy isEqual:peripheral.identifier]) {
            EasyPeripheral *tempP = self.foundDeviceDict[tempIndefy];
            tempP.deviceScanCount++ ;
            existedIndex = tempP.deviceScanCount ;
            break ;
        }
    }
    
    if (existedIndex == -1 ) {//扫描到了新设别
        EasyPeripheral *easyP = [[EasyPeripheral alloc]initWithPeripheral:peripheral central:self];
        easyP.RSSI = RSSI ;
        easyP.advertisementData = advertisementData ;
        [self.foundDeviceDict setObject:easyP forKey:easyP.identifier];
        if (_blueToothSearchDeviceCallback) {
            _blueToothSearchDeviceCallback(easyP , !self.isScanning );
        }
    }else if (existedIndex%10 == 0){//扫描到的此个设备超过10次
        EasyPeripheral *tempP = self.foundDeviceDict[peripheral.identifier];
        tempP.RSSI = RSSI ;
        tempP.deviceScanCount = 0 ;
        tempP.advertisementData = advertisementData ;
        if (_blueToothSearchDeviceCallback) {
            _blueToothSearchDeviceCallback(tempP , !self.isScanning );
        }
    }
}

#pragma mark - connect peripheral

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    EasyLog(@"\n蓝牙连接上一个设备：%@ %@",peripheral,peripheral.identifier);
    EasyPeripheral *existedP = nil ;
    for (NSUUID *tempIden in [self.connectedDeviceDict allKeys]) {
        if ([tempIden isEqual:peripheral.identifier]) {
            existedP = self.connectedDeviceDict[tempIden] ;
            break  ;
        }
    }
    
    if (!existedP) {
        for (NSUUID *tempIden in [self.foundDeviceDict allKeys]) {
            if ([tempIden isEqual:peripheral.identifier]) {
                existedP = self.foundDeviceDict[tempIden] ;
                break  ;
            }
        }
        [self.connectedDeviceDict setObject:existedP forKey:peripheral.identifier];
        
        [existedP dealDeviceConnectWithError:nil];
    }
    
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    EasyLog(@"\n蓝牙连接一个设备失败：%@ %@ %@",peripheral,peripheral.identifier,error);

    EasyPeripheral *existedP = nil ;
    for (NSUUID *tempP in [self.connectedDeviceDict allKeys]) {
        if ([tempP isEqual:peripheral.identifier]) {
            existedP = self.connectedDeviceDict[tempP];
            break  ;
        }
    }
    
    if (existedP) {
        [self.connectedDeviceDict removeObjectForKey:peripheral.identifier ];
    }
    else{
        
        for (NSUUID *tempIden in [self.foundDeviceDict allKeys]) {
            if ([tempIden isEqual:peripheral.identifier]) {
                existedP = self.foundDeviceDict[tempIden] ;
                break  ;
            }
        }
        EasyLog(@"attention: you should deal with this error");
    }
    
    NSAssert(existedP, @"attention: you should deal with this error");
    
//    existedP.errorDescription = error ;
    [existedP dealDeviceConnectWithError:error];
    
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    EasyLog(@"\n蓝牙一个设备失去连接：%@ %@ %@",peripheral,peripheral.identifier,error);

    EasyPeripheral *existedP = nil ;
    for (NSUUID *tempIden in [self.connectedDeviceDict allKeys]) {
        if ([tempIden isEqual:peripheral.identifier]) {
            existedP = self.connectedDeviceDict[tempIden] ;
            break  ;
        }
    }
    
    if (existedP) {
        for (EasyService *tempS in existedP.serviceArray) {
            tempS.service = nil;
            [tempS.characteristicArray removeAllObjects];
            tempS.isOn = NO;
            tempS.isEnabled = NO;
        }
        [existedP.serviceArray removeAllObjects];
        
        [self.connectedDeviceDict removeObjectForKey:existedP.identifier];
        
        [self.foundDeviceDict removeObjectForKey:existedP.identifier];
    }
    else{
        NSAssert(NO, @"attention: you should deal with this error");
    }
    
//    existedP.errorDescription = error ;

    if (error) {
        [existedP dealDisconnectWithError:error];
    }
    
}


- (NSArray *)retrieveConnectedPeripheralsWithServices:(NSArray *)serviceUUIDs
{
    EasyLog(@"\n根据服务的id获取所有系统已连接上的设备：%@",serviceUUIDs);

    if (!serviceUUIDs.count) {
        return @[];
    }
    
    NSArray *resultArray = [self.manager retrieveConnectedPeripheralsWithServices:serviceUUIDs];
    
    NSMutableArray *tempArray = [NSMutableArray arrayWithCapacity:resultArray.count];
    for (CBPeripheral *tempP in resultArray) {
        EasyPeripheral *tempPer = [[EasyPeripheral alloc]initWithPeripheral:tempP central:self];
        [tempArray addObject:tempPer];
    }
    return tempArray ;
}

- (NSArray *)retrievePeripheralsWithIdentifiers:(NSArray *)identifiers
{
    EasyLog(@"\n蓝牙获取系统所有已知设备：%@",identifiers);

    NSArray *resultArray = [self.manager retrievePeripheralsWithIdentifiers:identifiers];
    
    NSMutableArray *tempArray = [NSMutableArray arrayWithCapacity:resultArray.count];
    for (CBPeripheral *tempP in resultArray) {
        EasyPeripheral *tempPer = [[EasyPeripheral alloc]initWithPeripheral:tempP central:self];
        [tempArray addObject:tempPer];
    }
    return tempArray ;
}


#pragma mark - getter
- (NSMutableDictionary *)connectedDeviceDict
{
    if (nil == _connectedDeviceDict) {
        _connectedDeviceDict = [NSMutableDictionary dictionaryWithCapacity:10];
    }
    return _connectedDeviceDict ;
}
- (NSMutableDictionary *)foundDeviceDict
{
    if (nil == _foundDeviceDict) {
        _foundDeviceDict = [NSMutableDictionary dictionaryWithCapacity:10];
    }
    return _foundDeviceDict ;
}
@end
