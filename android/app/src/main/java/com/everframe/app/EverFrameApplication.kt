package com.everframe.app

import android.app.Application
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner

// 页面和录制服务共享同一个模型，锁屏或页面重建不会创建第二套录像索引。
class EverFrameApplication : Application(), ViewModelStoreOwner {
    override val viewModelStore = ViewModelStore()
    val model: AppModel by lazy {
        ViewModelProvider(this, ViewModelProvider.AndroidViewModelFactory.getInstance(this))[AppModel::class.java]
    }
}
