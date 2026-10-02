allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val projectRef = this
    val configureAndroid = Action<Project> {
        val androidExtension = extensions.findByName("android")
        if (androidExtension != null) {
            try {
                val method = androidExtension.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                method.invoke(androidExtension, 36)
            } catch (e: Exception) {
                try {
                    val setter = androidExtension.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                    setter.invoke(androidExtension, 36)
                } catch (ignored: Exception) {}
            }
        }
    }

    if (state.executed) {
        configureAndroid.execute(projectRef)
    } else {
        plugins.withId("com.android.library") { configureAndroid.execute(projectRef) }
        plugins.withId("com.android.application") { configureAndroid.execute(projectRef) }
    }
}