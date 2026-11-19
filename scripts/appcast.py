#!/usr/bin/env python3
"""Adds a new Vela version to the update feed (appcast.xml).

The appcast is an RSS file that Sparkle, Vela's updater, reads once a day.
Each <item> is one version: where to download it, its build number, its
signature, and its release notes. Beta builds carry <sparkle:channel>beta</…>,
so only people who turned on "Get beta updates" see them.

The release pipeline calls this; you never need to run it by hand.
"""
import argparse
import email.utils
import os
import re
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
KEEP = 30  # older versions drop off the end of the list


def s(tag):
    return f"{{{SPARKLE}}}{tag}"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--appcast", required=True)
    p.add_argument("--version", required=True, help="the version people see, like 1.1")
    p.add_argument("--build", required=True, help="the build number Sparkle compares")
    p.add_argument("--url", required=True, help="where the zip can be downloaded")
    p.add_argument("--signature", required=True, help='sign_update output: sparkle:edSignature="…" length="…"')
    p.add_argument("--notes", required=True, help="an HTML file with the release notes")
    p.add_argument("--channel", default="stable", choices=["stable", "beta"])
    p.add_argument("--min-macos", default="15.0")
    p.add_argument("--critical", action="store_true",
                   help="an urgent security fix: Sparkle asks to install it right away")
    a = p.parse_args()

    sig = re.search(r'edSignature="([^"]+)"', a.signature)
    length = re.search(r'length="(\d+)"', a.signature)
    if not sig or not length:
        raise SystemExit(f"Couldn't read the signature from: {a.signature!r}")

    if os.path.exists(a.appcast):
        tree = ET.parse(a.appcast)
        rss = tree.getroot()
        channel = rss.find("channel")
    else:
        rss = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "Vela"
        ET.SubElement(channel, "description").text = "Updates for the Vela browser"
        tree = ET.ElementTree(rss)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Vela {a.version}"
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, s("version")).text = a.build
    ET.SubElement(item, s("shortVersionString")).text = a.version
    ET.SubElement(item, s("minimumSystemVersion")).text = a.min_macos
    if a.channel == "beta":
        ET.SubElement(item, s("channel")).text = "beta"
    if a.critical:
        # Sparkle shows critical updates straight away, even if you skipped
        # an earlier version, and won't let you "Skip This Version".
        ET.SubElement(item, s("criticalUpdate"))
    with open(a.notes, encoding="utf-8") as f:
        ET.SubElement(item, "description").text = f.read()
    ET.SubElement(item, "enclosure", {
        "url": a.url,
        s("edSignature"): sig.group(1),
        "length": length.group(1),
        "type": "application/octet-stream",
    })

    # Newest first, right after the channel's title and description.
    items = channel.findall("item")
    insert_at = list(channel).index(items[0]) if items else len(channel)
    channel.insert(insert_at, item)
    for old in channel.findall("item")[KEEP:]:
        channel.remove(old)

    ET.indent(tree, space="  ")
    tree.write(a.appcast, encoding="utf-8", xml_declaration=True)
    print(f"✓ Added Vela {a.version} (build {a.build}, {a.channel}{', critical' if a.critical else ''}) to {a.appcast}")


if __name__ == "__main__":
    main()
