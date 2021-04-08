/*
 * Copyright 2021 Miklos Maroti.
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this software; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street,
 * Boston, MA 02110-1301, USA.
 */

#include <iio.h>
#include <unistd.h>
#include <cassert>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <iomanip>
#include <iostream>

static bool stop = false;
static void handle_sig(int) { stop = true; }

int main(int argc, char** argv)
{
    const char* context_uri = "local:";
    float samp_rate = 5.0f;
    float frequency = 2.4f;
    float bandwidth = 4.0f;
    unsigned int buff_size = 1024;

    int opt;
    while ((opt = getopt(argc, argv, "u:r:f:w:b:h")) != -1) {
        switch (opt) {
        case 'u':
            context_uri = optarg;
            break;
        case 'r':
            samp_rate = std::atof(optarg);
            break;
        case 'f':
            frequency = std::atof(optarg);
            break;
        case 'w':
            bandwidth = std::atof(optarg);
            break;
        case 'b':
            buff_size = (unsigned int)std::max(1, std::atoi(optarg));
            break;
        case 'h':
        default:
            std::cerr << "Usage: ad9361_rx [-options]\n"
                      << "\t-u iio context URI (default: " << context_uri << ")\n"
                      << "\t-r sampling rate in Msps (default " << samp_rate << ")\n"
                      << "\t-f center frequency in GHz (default " << frequency << ")\n"
                      << "\t-w rx bandwidth in MHz (default " << bandwidth << ")\n"
                      << "\t-b buffer size in 1k samples (default " << buff_size << ")\n"
                      << "\t-h prints this help message\n";
            return 1;
        }
    }

    signal(SIGINT, handle_sig);

    std::cout << "Creating IIO context" << std::endl;
    struct iio_context* context = iio_create_context_from_uri(context_uri);
    if (context == nullptr) {
        std::cerr << "Unknown context: " << context_uri << std::endl;
        return 1;
    }

    std::cout << "Finding ad9361-phy device" << std::endl;
    struct iio_device* phydev = iio_context_find_device(context, "ad9361-phy");

    std::cout << "Finding ad9361-phy rx1 controll channel" << std::endl;
    struct iio_channel* chn = iio_device_find_channel(phydev, "voltage0", false);
    assert(chn != nullptr);

    std::cout << "Setting rx port to A_BALANCED" << std::endl;
    ssize_t ret = iio_channel_attr_write(chn, "rf_port_select", "A_BALANCED");
    assert(ret >= 0);

    std::cout << "Setting rx bandwidth to " << bandwidth << " MHz" << std::endl;
    ret = iio_channel_attr_write_longlong(chn, "rf_bandwidth", bandwidth * 1e6f);
    assert(ret >= 0);

    std::cout << "Setting sampling frequency to " << samp_rate << " Msps" << std::endl;
    ret = iio_channel_attr_write_longlong(chn, "sampling_frequency", samp_rate * 1e6f);
    assert(ret >= 0);

    std::cout << "Finding ad9361-phy rx local oscillator channel" << std::endl;
    chn = iio_device_find_channel(phydev, "altvoltage0", true);
    assert(chn != nullptr);

    std::cout << "Setting center frequency to " << frequency << " GHz" << std::endl;
    ret = iio_channel_attr_write_longlong(chn, "frequency", frequency * 1e9f);
    assert(ret >= 0);
    (void)ret;

    std::cout << "Finding cf-ad9361-lpc device" << std::endl;
    struct iio_device* device = iio_context_find_device(context, "cf-ad9361-lpc");
    assert(device != nullptr);

    std::cout << "Finding cf-ad9361-lpc streaming channels" << std::endl;
    struct iio_channel* channel_i = iio_device_find_channel(device, "voltage0", false);
    struct iio_channel* channel_q = iio_device_find_channel(device, "voltage1", false);

    std::cout << "Enabling cf-ad9361-lpc streaming channels" << std::endl;
    iio_channel_enable(channel_i);
    iio_channel_enable(channel_q);

    std::cout << "Creating buffer for " << buff_size * 1024 << " samples" << std::endl;
    struct iio_buffer* buffer = iio_device_create_buffer(device, buff_size * 1024, false);
    assert(buffer != nullptr);

    std::chrono::time_point<std::chrono::system_clock> time1 =
        std::chrono::system_clock::now();

    // https://github.com/analogdevicesinc/libiio/blob/master/tests/iio_adi_xflow_check.c
    iio_device_reg_write(device, 0x80000088, 4);

    std::cout << "Starting streaming (press CTRL+C to cancel)" << std::endl;
    while (!stop) {
        ssize_t nbytes_rx = iio_buffer_refill(buffer);
        if (nbytes_rx < 0) {
            std::cout << "Error refilling buffer" << std::endl;
            break;
        }

        int16_t m0 = 0;
        int16_t m1 = 0;
        int16_t m2 = 0;
        int16_t m3 = 0;

        int16_t* data = (int16_t*)iio_buffer_first(buffer, channel_i);
        int count = ((int16_t*)iio_buffer_end(buffer) - data) / 2;
        for (int i = 0; i < 2 * count; i += 4) {
            int16_t a0 = data[i + 0]; // I0
            int16_t a1 = data[i + 1]; // Q0
            int16_t a2 = data[i + 2]; // I1
            int16_t a3 = data[i + 3]; // Q1

            a0 = std::abs(a0);
            a1 = std::abs(a1);
            a2 = std::abs(a2);
            a3 = std::abs(a3);

            m0 = std::max(m0, a0);
            m1 = std::max(m1, a1);
            m2 = std::max(m2, a2);
            m3 = std::max(m3, a3);
        }

        int16_t ampl = std::max(std::max(m0, m1), std::max(m2, m3));

        std::chrono::time_point<std::chrono::system_clock> time2 =
            std::chrono::system_clock::now();

        float rate =
            (float)count /
            std::chrono::duration_cast<std::chrono::microseconds>(time2 - time1).count();
        time1 = time2;

        uint32_t irqs;
        iio_device_reg_read(device, 0x80000088, &irqs);
        iio_device_reg_write(device, 0x80000088, 4);
        bool overflow = irqs & 4;

        std::cout << "Received " << count << " samples, " << std::fixed
                  << std::setprecision(3) << rate << " msps, max amplitude " << ampl
                  << ", overflow " << (overflow ? "yes" : "no") << std::endl;
    }

    std::cout << "Destroying buffer" << std::endl;
    iio_buffer_destroy(buffer);

    std::cout << "Disabling cf-ad9361-lpc streaming channels" << std::endl;
    iio_channel_disable(channel_i);
    iio_channel_disable(channel_q);

    std::cout << "Destroying context" << std::endl;
    iio_context_destroy(context);

    return 0;
}
