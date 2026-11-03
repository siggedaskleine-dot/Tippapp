plugins {
    kotlin("jvm")
    application
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }

repositories { mavenCentral() }

dependencies { implementation(project(":core")) }

application { mainClass.set("tipsapp.cli.MainKt") }
