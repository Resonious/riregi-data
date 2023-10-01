import 'dart:developer';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef RRGetErrorNative = Pointer<Utf8> Function();
typedef RRGetError = Pointer<Utf8> Function();
typedef RRStartNative = Pointer<Void> Function(Uint32);
typedef RRStart = Pointer<Void> Function(Uint32);
typedef RRCleanupNative = Void Function(Pointer<Void>);
typedef RRCleanup = void Function(Pointer<Void>);
typedef RRMenuLenNative = Uint32 Function(Pointer<Void>);
typedef RRMenuLen = int Function(Pointer<Void>);
typedef RRMenuAddNative = Int Function(
    Pointer<Void>, Int64, Pointer<Utf8>, Uint32, Pointer<Utf8>, Uint32);
typedef RRMenuAdd = int Function(
    Pointer<Void>, Int64, Pointer<Utf8>, Uint32, Pointer<Utf8>, Uint32);
typedef RRMenuUpdateNative = Int Function(
    Pointer<Void>, Uint32, Int64, Pointer<Utf8>, Uint32, Pointer<Utf8>, Uint32);
typedef RRMenuUpdate = int Function(
    Pointer<Void>, Uint32, Int64, Pointer<Utf8>, Uint32, Pointer<Utf8>, Uint32);
typedef RRMenuRemoveNative = Int Function(Pointer<Void>, Uint32);
typedef RRMenuRemove = int Function(Pointer<Void>, Uint32);
typedef RRMenuItemNameNative = Pointer<Utf8> Function(Pointer<Void>, Uint32);
typedef RRMenuItemName = Pointer<Utf8> Function(Pointer<Void>, Uint32);
typedef RRMenuItemImagePathNative = Pointer<Utf8> Function(
    Pointer<Void>, Uint32);
typedef RRMenuItemImagePath = Pointer<Utf8> Function(Pointer<Void>, Uint32);
typedef RRMenuItemPriceNative = Int64 Function(Pointer<Void>, Uint32);
typedef RRMenuItemPrice = int Function(Pointer<Void>, Uint32);
typedef RRMenuItemSetNameNative = Int Function(
    Pointer<Void>, Uint32, Pointer<Utf8>, Uint32);
typedef RRMenuItemSetName = int Function(
    Pointer<Void>, Uint32, Pointer<Utf8>, Uint32);
typedef RRMenuItemSetImagePathNative = Int Function(
    Pointer<Void>, Uint32, Pointer<Utf8>, Uint32);
typedef RRMenuItemSetImagePath = int Function(
    Pointer<Void>, Uint32, Pointer<Utf8>, Uint32);
typedef RRMenuItemSetPriceNative = Int Function(Pointer<Void>, Uint32, Int64);
typedef RRMenuItemSetPrice = int Function(Pointer<Void>, Uint32, Int64);
typedef RROrdersLenNative = Uint64 Function(Pointer<Void>);
typedef RROrdersLen = int Function(Pointer<Void>);
typedef RRCurrentOrderLenNative = Uint32 Function(Pointer<Void>);
typedef RRCurrentOrderLen = int Function(Pointer<Void>);
typedef RRCurrentOrderTotalNative = Int64 Function(Pointer<Void>);
typedef RRCurrentOrderTotal = int Function(Pointer<Void>);
typedef RRAddItemToOrderNative = Int Function(Pointer<Void>, Uint32);
typedef RRAddItemToOrder = int Function(Pointer<Void>, Uint32);
typedef RRRemoveOrderItemNative = Int Function(Pointer<Void>, Uint32);
typedef RRRemoveOrderItem = int Function(Pointer<Void>, Uint32);
typedef RROrderItemNameNative = Pointer<Utf8> Function(Pointer<Void>, Uint32);
typedef RROrderItemName = Pointer<Utf8> Function(Pointer<Void>, Uint32);
typedef RROrderItemImagePathNative = Pointer<Utf8> Function(
    Pointer<Void>, Uint32);
typedef RROrderItemImagePath = Pointer<Utf8> Function(Pointer<Void>, Uint32);
typedef RROrderItemPriceNative = Int64 Function(Pointer<Void>, Uint32);
typedef RROrderItemPrice = int Function(Pointer<Void>, Uint32);

class ActiveAppState {
  final DynamicLibrary lib;
  final String dataPath;

  late final RRGetError rrGetError;
  late final RRStart rrStart;
  late final RRCleanup rrCleanup;
  late final RRMenuLen rrMenuLen;
  late final RRMenuAdd rrMenuAdd;
  late final RRMenuUpdate rrMenuUpdate;
  late final RRMenuRemove rrMenuRemove;
  late final RRMenuItemName rrMenuItemName;
  late final RRMenuItemImagePath rrMenuItemImagePath;
  late final RRMenuItemPrice rrMenuItemPrice;
  late final RRMenuItemSetName rrMenuItemSetName;
  late final RRMenuItemSetImagePath rrMenuItemSetImagePath;
  late final RRMenuItemSetPrice rrMenuItemSetPrice;
  late final RROrdersLen rrOrdersLen;
  late final RRCurrentOrderLen rrCurrentOrderLen;
  late final RRCurrentOrderTotal rrCurrentOrderTotal;
  late final RRAddItemToOrder rrAddItemToOrder;
  late final RRRemoveOrderItem rrRemoveOrderItem;
  late final RROrderItemName rrOrderItemName;
  late final RROrderItemImagePath rrOrderItemImagePath;
  late final RROrderItemPrice rrOrderItemPrice;

  late final Pointer<Void> ctx;

  ActiveAppState({required this.lib, required this.dataPath}) {
    rrGetError =
        lib.lookupFunction<RRGetErrorNative, RRGetError>("rr_get_error");
    rrStart = lib.lookupFunction<RRStartNative, RRStart>("rr_start");
    rrCleanup = lib.lookupFunction<RRCleanupNative, RRCleanup>("rr_cleanup");
    rrMenuLen = lib.lookupFunction<RRMenuLenNative, RRMenuLen>("rr_menu_len");
    rrMenuAdd = lib.lookupFunction<RRMenuAddNative, RRMenuAdd>("rr_menu_add");
    rrMenuUpdate =
        lib.lookupFunction<RRMenuUpdateNative, RRMenuUpdate>("rr_menu_update");
    rrMenuRemove =
        lib.lookupFunction<RRMenuRemoveNative, RRMenuRemove>("rr_menu_remove");
    rrMenuItemName = lib.lookupFunction<RRMenuItemNameNative, RRMenuItemName>(
        "rr_menu_item_name");
    rrMenuItemImagePath =
        lib.lookupFunction<RRMenuItemImagePathNative, RRMenuItemImagePath>(
            "rr_menu_item_image_path");
    rrMenuItemPrice =
        lib.lookupFunction<RRMenuItemPriceNative, RRMenuItemPrice>(
            "rr_menu_item_price");
    rrMenuItemSetName =
        lib.lookupFunction<RRMenuItemSetNameNative, RRMenuItemSetName>(
            "rr_menu_item_set_name");
    rrMenuItemSetImagePath = lib.lookupFunction<RRMenuItemSetImagePathNative,
        RRMenuItemSetImagePath>("rr_menu_item_set_image_path");
    rrMenuItemSetPrice =
        lib.lookupFunction<RRMenuItemSetPriceNative, RRMenuItemSetPrice>(
            "rr_menu_item_set_price");
    rrOrdersLen =
        lib.lookupFunction<RROrdersLenNative, RROrdersLen>("rr_orders_len");
    rrCurrentOrderLen =
        lib.lookupFunction<RRCurrentOrderLenNative, RRCurrentOrderLen>(
            "rr_current_order_len");
    rrCurrentOrderTotal =
        lib.lookupFunction<RRCurrentOrderTotalNative, RRCurrentOrderTotal>(
            "rr_current_order_total");
    rrAddItemToOrder =
        lib.lookupFunction<RRAddItemToOrderNative, RRAddItemToOrder>(
            "rr_add_item_to_order");
    rrRemoveOrderItem =
        lib.lookupFunction<RRRemoveOrderItemNative, RRRemoveOrderItem>(
            "rr_remove_order_item");
    rrOrderItemName =
        lib.lookupFunction<RROrderItemNameNative, RROrderItemName>(
            "rr_order_item_name");
    rrOrderItemImagePath =
        lib.lookupFunction<RROrderItemImagePathNative, RROrderItemImagePath>(
            "rr_order_item_image_path");
    rrOrderItemPrice =
        lib.lookupFunction<RROrderItemPriceNative, RROrderItemPrice>(
            "rr_order_item_price");

    final path = dataPath.toNativeUtf8();
    ctx = rrStart(path, path.length);
    if (ctx.address == 0) {
      log('we have a problem');
    }
  }
}
