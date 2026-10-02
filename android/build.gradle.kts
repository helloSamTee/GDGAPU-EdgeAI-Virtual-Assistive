allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// The camera_android_camerax plugin (CameraX 1.5.x) references
// androidx.concurrent.futures.CallbackToFutureAdapter through a @NonNull
// annotation on SurfaceRequest, but that library isn't on its compile
// classpath — which fails compileDebugJavaWithJavac. Add it explicitly to
// the plugin module.
subprojects {
    if (project.name == "camera_android_camerax") {
        project.afterEvaluate {
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

plugins {
    id("com.google.gms.google-services") version "4.5.0" apply false
}
