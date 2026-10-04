# ProGuard/R8 rules for the triangle example
#
# Referenced from build.gradle (buildTypes.release.proguardFiles).
# minifyEnabled is set to false, so nothing here is applied yet; add rules
# here before turning minification/shrinking on.
#
# Native code is unaffected by R8, but if you enable minification keep the
# JNI entry points reachable, e.g.:
# -keep class de.saschawillems.vulkanSample.VulkanActivity { *; }
