


import numpy as np
import pandas as pd
from scipy.stats import skew, kurtosis
from sklearn.model_selection import train_test_split




def extract_ps2_features(signal):
    ps2_skew = skew(signal, bias=False)
    ps2_kurt = kurtosis(signal, fisher=False, bias=False)
    return ps2_skew, ps2_kurt




    ps2 = np.loadtxt(
        data_path + "/PS2.txt",
        delimiter="\t"
    )

    valve_condition = profile[:, 1]

    label_map = {
        100: 0,
        90: 1,
        80: 2,
        73: 3
    }

    samples = []


    return pd.DataFrame(samples)


def select_cycles(all_data, cycle_file):

    selected = pd.read_csv(cycle_file)

    data = all_data[
        all_data["cycle"].isin(selected["cycle"])
    ]

    return data.reset_index(drop=True)


def split_data(data):

    train, test = train_test_split(
        data,
        test_size=0.3,
        random_state=RANDOM_STATE,
        stratify=data["label"]
    )

    return train, test


def main():

    data_path = "./UCI_hydraulic"

    all_data = load_and_extract(data_path)

    all_data.to_csv(
        "hydraulic_all_PS2_features.csv",
        index=False
    )

    final_data = select_cycles(
        all_data,
        "selected_cycles.csv"
    )



    train, test = split_data(final_data)

    train.to_csv(
        "hydraulic_train.csv",
        index=False
    )

    test.to_csv(
        "hydraulic_test.csv",
        index=False
    )

    print("All samples:", len(all_data))
    print("Experimental samples:", len(final_data))
    print("Train:", len(train))
    print("Test:", len(test))
    print(final_data["label"].value_counts())


if __name__ == "__main__":
    main()
