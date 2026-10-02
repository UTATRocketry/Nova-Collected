# Roadmap

What the software team is working towards this year (2026/27), and why.

> [!NOTE]
> This is a living plan, not a commitment. Leads reorder it as test dates and
> priorities change. Specific bugs and gaps are tracked as issues and listed in
> [SUPPORT.md](SUPPORT.md#known-issues), not here.

## 2026/27 focus: performance and maintainability

Nova now has a working release process, station config history and full
avionics support. This year is about making it **fast and measurable** and
**easy to change safely**, rather than adding large features.

## Performance

Know how fast Nova is, then make the slow paths faster. Every performance
change starts from a measurement.

- [ ] **Measure end-to-end latency**: from a sensor to the operator's screen,
      and from a click to the actuator moving. Record how it was measured, so
      later changes can be compared.
- [ ] **Measure the network**: throughput and latency across the station
      network, including the wireless link to the operator station.
- [ ] **Make telemetry delivery efficient**: send operators only the data they
      need, as often as they need it.
- [ ] **Keep the UI smooth at full telemetry rate**, on the operator laptop.
- [ ] **Get the most out of the avionics link**: choose the link and data
      rates that give operators the flight-computer data they need.
- [ ] **Use the full sensor sample rate** where it adds value, in live views
      and recordings.

## Maintainability

Make Nova easier to understand, change and trust.

- [ ] **Remove what isn't used**: dead code, legacy tools and scripts left from
      earlier setups.
- [ ] **Keep docs and code in step**: every PR that changes behaviour updates
      the docs it affects.
- [ ] **Test more automatically**: a green test suite in every repo, simulator
      tests in CI, and a written hands-on testing procedure.
- [ ] **Lint and format in CI** for every language in every repo.
- [ ] **One definition per contract**: shared message formats and protocols
      are defined once and checked by tests on both sides.
- [ ] **Smaller, modular components**: split the largest files and scripts
      into parts a new member can follow.
- [ ] **Data that explains itself**: every recording identifies the software
      and calibration it was taken with, and is easy to archive and share.

## Future considerations

Not scheduled; to be decided.

- Automatic upload of recording archives to the team's shared Drive.
- One-step setup for operator laptops.
