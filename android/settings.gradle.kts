pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "tipsapp-android"
include(":app")
// Datagrunden och analysmotorn delas med kommandoradsverktyget i roten
include(":core")
project(":core").projectDir = file("../core")
