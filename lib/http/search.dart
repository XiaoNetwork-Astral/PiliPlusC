import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/models/search/suggest.dart';
import 'package:PiliPlus/models_new/dynamic/dyn_topic_pub_search/data.dart';
import 'package:PiliPlus/models_new/pagelist/page_item.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/search/search_rcmd/data.dart';
import 'package:PiliPlus/models_new/search/search_trending/data.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai_filter_helper.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/request_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/wbi_sign.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

abstract final class SearchHttp {
  /// 视频结果判定文本：标题（UP主：xxx）
  static String _videoText(SearchVideoItemModel item) {
    final name = item.owner.name;
    if (name == null || name.isEmpty) {
      return item.title;
    }
    return '${item.title}（UP主：$name）';
  }

  /// 视频的简单快照，键与值都是简单类型
  static Map<String, dynamic> _videoMeta(SearchVideoItemModel item) {
    final owner = item.owner;
    final uname = owner.name;
    final mid = owner.mid;
    return <String, dynamic>{
      'type': 'video',
      if (item.bvid != null) 'bvid': item.bvid,
      if (item.aid != null) 'aid': item.aid,
      'title': item.title,
      if (uname != null && uname.isNotEmpty) 'uname': uname,
      if (mid != null) 'mid': mid,
      if (item.cover != null && item.cover!.isNotEmpty) 'cover': item.cover,
      if (item.duration > 0) 'duration': item.duration,
    };
  }

  /// 从搜索结果里按 bvid 收集原始 JSON，供屏蔽时做快照
  static Map<String, Map<String, dynamic>> _rawVideoItemsOf(
    Map<String, dynamic> data,
  ) {
    final result = <String, Map<String, dynamic>>{};
    void addRaw(Object? raw) {
      if (raw is Map && raw['bvid'] is String) {
        result[raw['bvid'] as String] = Map<String, dynamic>.from(raw);
      }
    }

    final list = data['result'];
    if (list is List) {
      for (final item in list) {
        if (item is Map && item['data'] is List) {
          for (final raw in item['data'] as List) {
            addRaw(raw);
          }
        } else {
          addRaw(item);
        }
      }
    }
    return result;
  }

  // 获取搜索建议
  @pragma('vm:notify-debugger-on-exception')
  static Future<LoadingState<SearchSuggestModel>> searchSuggest({
    required String term,
  }) async {
    final res = await Request().get(
      Api.searchSuggest,
      queryParameters: await WbiSign.makSign({
        'term': term,
        'highlight': 0,
        'spmid': 333.1365,
        'web_location': 333.1365,
      }),
    );
    final resData = res.data;
    if (resData is Map && resData['code'] == 0) {
      try {
        return Success(SearchSuggestModel.fromJson(resData['data']['result']));
      } catch (_) {
        if (kDebugMode) rethrow;
      }
    }
    return const Error(null);
  }

  // 分类搜索
  @pragma('vm:notify-debugger-on-exception')
  static Future<LoadingState<R>> searchByType<R extends SearchNumData>({
    required SearchType searchType,
    required String keyword,
    required page,
    String? order,
    int? duration,
    int? tids,
    int? orderSort,
    int? userType,
    int? categoryId,
    int? pubBegin,
    int? pubEnd,
    String? gaiaVtoken,
    required ValueChanged<String> onSuccess,
  }) async {
    String api = searchType.api;
    var params = await WbiSign.makSign({
      'search_type': searchType.name,
      'keyword': keyword,
      'page': page,
      if (order != null && order.isNotEmpty) 'order': order,
      'duration': ?duration,
      'tids': ?tids,
      'order_sort': ?orderSort,
      'user_type': ?userType,
      'category_id': ?categoryId,
      'pubtime_begin_s': ?pubBegin,
      'pubtime_end_s': ?pubEnd,
      'page_size': 20,
      'platform': 'pc',
      'web_location': 1430654,
      'gaia_vtoken': ?gaiaVtoken,
    });
    if (searchType == SearchType.media_hk_bangumi) {
      if (Pref.apiHKUrl.isEmpty) {
        return const Error('请在 设置-其他设置-港澳台代理 中设置代理服务器');
      }
      params['search_type'] = SearchType.media_bangumi.name;
      api = Pref.apiHKUrl + Api.searchByType;
    }
    final res = await Request().get(
      api,
      queryParameters: params,
      options: Options(
        headers: {
          if (gaiaVtoken != null) 'cookie': 'x-bili-gaia-vtoken=$gaiaVtoken',
          'origin': 'https://search.bilibili.com',
          'referer':
              'https://search.bilibili.com/${searchType.name}?keyword=${Uri.encodeFull(keyword)}',
        },
      ),
    );
    final resData = res.data;
    if (resData is Map) {
      if (resData['code'] == 0) {
        final Map<String, dynamic> dataData = resData['data'];
        final vVoucher = dataData['v_voucher'];
        if (vVoucher != null) {
          RequestUtils.validate(vVoucher, onSuccess);
          return const Error('触发风控');
        }
        try {
          final R data = switch (searchType) {
            .all => SearchVideoData.fromSearchAll(dataData),
            .video => SearchVideoData.fromJson(dataData),
            .media_bangumi ||
            .media_hk_bangumi ||
            .media_ft => SearchPgcData.fromJson(dataData),
            .live_room => SearchLiveData.fromJson(dataData),
            .bili_user => SearchUserData.fromJson(dataData),
            .article => SearchArticleData.fromJson(dataData),
          } as R;
          // 只处理视频结果，用户/番剧/专栏等不接 AI
          if (data is SearchVideoData) {
            final items = data.list;
            if (items != null && items.isNotEmpty) {
              final rawByBvid = _rawVideoItemsOf(dataData);
              data.list = await aiFilterList<SearchVideoItemModel>(
                surface: FilterSurface.video,
                items: items,
                textOf: _videoText,
                midOf: (e) => e.owner.mid,
                metaOf: _videoMeta,
                snapshotOf: (e) {
                  final raw = rawByBvid[e.bvid];
                  return raw == null
                      ? null
                      : <String, dynamic>{
                          'json': raw,
                          'model': 'SearchVideoItemModel',
                        };
                },
              );
            }
          }
          return Success(data);
        } catch (e, s) {
          return Error('$e\n\n$s');
        }
      } else {
        return Error(resData['message'], code: resData['code']);
      }
    } else {
      return const Error('服务器错误');
    }
  }

  static Future<int?> ab2c({dynamic aid, dynamic bvid, int? part}) async {
    return (await ab2cWithDimension(aid: aid, bvid: bvid, part: part))?.cid;
  }

  static Future<PageItem?> ab2cWithDimension({
    dynamic aid,
    dynamic bvid,
    int? part,
  }) async {
    final res = await Request().get(
      Api.ab2c,
      queryParameters: {'aid': ?aid, 'bvid': ?bvid},
    );
    if (res.data['code'] == 0) {
      if (res.data['data'] case List list) {
        final target = part != null
            ? (list.getOrNull(part - 1) ?? list.firstOrNull)
            : list.firstOrNull;
        if (target != null) {
          return PageItem.fromJson(target);
        }
      }
      return null;
    } else {
      SmartDialog.showToast("ab2c error: ${res.data['message']}");
      return null;
    }
  }

  static Future<LoadingState<PgcInfoModel>> pgcInfo({
    dynamic seasonId,
    dynamic epId,
  }) async {
    final res = await Request().get(
      Api.pgcInfo,
      queryParameters: {
        'season_id': ?seasonId,
        'ep_id': ?epId,
      },
    );
    if (res.data['code'] == 0) {
      return Success(PgcInfoModel.fromJson(res.data['result']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<PgcInfoModel>> pugvInfo({
    dynamic seasonId,
    dynamic epId,
  }) async {
    final res = await Request().get(
      Api.pugvInfo,
      queryParameters: {
        'season_id': ?seasonId,
        'ep_id': ?epId,
      },
    );
    if (res.data['code'] == 0) {
      return Success(PgcInfoModel.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  // static Future<LoadingState> episodeInfo({dynamic epId}) async {
  //   final res = await Request().get(
  //     Api.episodeInfo,
  //     queryParameters: {
  //       'ep_id': ?epId,
  //     },
  //   );
  //   if (res.data['code'] == 0) {
  //     return Success(res.data['data']);
  //   } else {
  //     return Error(res.data['message']);
  //   }
  // }

  static Future<LoadingState<SearchTrendingData>> searchTrending({
    int limit = 30,
    bool needsTop = false,
  }) async {
    final res = await Request().get(
      Api.searchTrending,
      queryParameters: {
        'limit': limit,
      },
    );
    if (res.data['code'] == 0) {
      return Success(
        SearchTrendingData.fromJson(res.data['data'], needsTop: needsTop),
      );
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<SearchRcmdData>> searchRecommend() async {
    final res = await Request().get(
      Api.searchRecommend,
      queryParameters: {
        'build': 8430300,
        'channel': 'master',
        'version': '8.43.0',
        'c_locale': 'zh_CN',
        'mobi_app': 'android',
        'platform': 'android',
        's_locale': 'zh_CN',
        'from': 2,
      },
    );
    if (res.data['code'] == 0) {
      return Success(SearchRcmdData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<TopicPubSearchData>> topicPubSearch({
    required String keywords,
    String content = '',
    required int pageNum,
  }) async {
    final res = await Request().get(
      Api.topicPubSearch,
      queryParameters: {
        'keywords': keywords,
        'content': content,
        if (pageNum == 1) ...{
          'page_size': 20,
          'page_num': 1,
        } else
          'offset': 20 * (pageNum - 1),
        'web_location': 333.1365,
      },
    );
    if (res.data['code'] == 0) {
      return Success(TopicPubSearchData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }
}
